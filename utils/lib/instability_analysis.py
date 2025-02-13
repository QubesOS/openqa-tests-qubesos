from sqlalchemy import select

from lib.openqa_api import (
    OpenQA,
    get_db_session,
    ChildJob,
    OrphanJob,
    TestFailure,
)

class InstabilityAnalysis:
    """Job Instability Analysis"""

    def __init__(self, original_jobs):
        self.unstable_jobs = {} # JobData -> ChildJobInstability

        jobs = original_jobs

        for job in jobs:
            t = ChildJobInstability(job)
            if t.is_unstable:
                self.unstable_jobs[job] = t

    def is_test_unstable(self, sample_test):
        for job in self.unstable_jobs:
            if sample_test.job == job:
                return self.unstable_jobs[job].is_test_unstable(sample_test)
        return False

    def report(self, details=False):
        text = "<details>\n\n"
        for job_instability in self.unstable_jobs.values():
            text += job_instability.report(details)
        text += "\n</details>\n\n"
        return text

class AbstractInstability:
    @property
    def is_unstable(self):
        return False

    def report(self, details=False):
        return "abstract report"

class ChildJobInstability(AbstractInstability):

    def __init__(self, job):
        self.unstable_tests = []
        self.test_instability = []
        self.job = job

        # obtain jobs' stability from the update pool since those don't have
        # pull requests included (thus more accurate results)
        jobs = OpenQA.get_n_jobs_like(job, n=5, flavor_override="update")
        job_ids = [job.job_id for job in jobs]

        db = get_db_session()
        test_identifiers = db.execute(
            select(TestFailure.name, TestFailure.title, TestFailure.test_id)\
            .where(TestFailure.job_id.in_(job_ids))\
            .group_by(TestFailure.title, TestFailure.name, TestFailure.test_id))

        for (test_name, test_title, test_id) in test_identifiers:
            sample_test_failure = db.query(TestFailure)\
                .filter(TestFailure.name == test_name)\
                .filter(TestFailure.title == test_title)\
                .filter(TestFailure.test_id == test_id)\
                .where(TestFailure.job_id.in_(job_ids))\
                .first()

            t = TestInstability(sample_test_failure, job_ids)
            if t.is_unstable:
                self.unstable_tests += [sample_test_failure]
                self.test_instability += [t]

    @property
    def is_unstable(self):
        return len(self.unstable_tests) > 0

    def is_test_unstable(self, test_failure):
        return test_failure in self.unstable_tests

    def report(self, details=False):
        if len(self.unstable_tests) == 0:
            return ""

        text = "* {}\n".format(self.job.get_job_combined_name())
        for test_instability in self.test_instability:
            text += test_instability.report(details)
        text += "\n"
        return text


class TestInstability(AbstractInstability):

    def __init__(self, sample_test_failure, job_ids):
        self.job_ids = job_ids
        self.sample_test_failure = sample_test_failure
        self.past_failures = self._get_past_failures()

    def _get_past_failures(self):
        test_name = self.sample_test_failure.name
        test_title = self.sample_test_failure.title
        test_id = self.sample_test_failure.test_id

        db = get_db_session()
        past_failures = db.query(TestFailure)\
                          .where(TestFailure.job_id.in_(self.job_ids))\
                          .filter(TestFailure.name == test_name)\
                          .filter(TestFailure.title == test_title)\
                          .filter(TestFailure.test_id == test_id)\
                          .all()
        return past_failures

    @property
    def is_unstable(self):
        historical_data_len = len(self.job_ids)

        # always succeded
        if len(self.past_failures) == 0:
            return False

        # succeded only sometimes
        elif len(self.past_failures) != historical_data_len:
            return True

        # never succeeded
        else:
            errors = [failure.relevant_error for failure in self.past_failures]
            unique_errors = list(set(errors))
            return len(unique_errors) != 1

    def report(self, details=False):
        if self.is_unstable:
            test_name = self.sample_test_failure.name
            test_title = self.sample_test_failure.title
            if details:
                text = "  <details><summary>{}/{}"\
                    .format(test_name, test_title)
                text += " ({}/{} times with errors)</summary>\n\n".format(
                    len(self.past_failures), len(self.job_ids))
                for fail in self.past_failures:
                    text += "   - [job {}]({}) `{}`\n".format(
                        fail.job.job_id,
                        fail.get_test_url(),
                        fail.relevant_error)
                text += "  </details>\n\n"
            else:
                text = "  * {}/{}\n".format(test_name, test_title)
                text += " ({}/{} times with errors\n\n)".format(
                    len(self.past_failures), len(self.job_ids))
            return text
        else:
            return ""

