from lib.openqa_api import (
    OpenQA,
    get_db_session,
    JobData,
    TestFailure,
    ChildJob
)
from sqlalchemy import select

def report_unstable_tests(reference_job):
    if not isinstance(reference_job, ChildJob):
        raise Exception("unstable reporting only possible with child jobs")

    jobs = OpenQA.get_n_jobs_like(reference_job, n=5)
    job_ids = [job.job_id for job in jobs]

    db = get_db_session()
    test_identifiers = db.execute(
        select(TestFailure.name, TestFailure.title, TestFailure.test_id)\
        .where(TestFailure.job_id.in_(job_ids))\
        .group_by(TestFailure.title, TestFailure.name, TestFailure.test_id))

    text = ""
    for test_identier in test_identifiers:
        (test_name, test_title, _) = test_identier
        errors = get_test_errors_in_jobs(db, test_identier, job_ids)

        if len(errors) > 0:
            unique_errors = list(set(errors))
            if len(unique_errors) != 1:
                text += "  * {}/{}\n".format(test_name, test_title)
    return text

def get_test_errors_in_jobs(db, test_identifier, job_ids):
    (test_name, test_title, test_id) = test_identifier

    rows = db.execute(
                select(TestFailure.relevant_error)
                .where(TestFailure.job_id.in_(job_ids))\
                .filter(TestFailure.name == test_name)\
                .filter(TestFailure.title == test_title)\
                .filter(TestFailure.test_id == test_id)).all()

    return [error for (error,) in rows]
