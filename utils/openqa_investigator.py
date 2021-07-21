from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap

HISTORY_LEN = 200

def historical_test_failures(test_name, test_title):
    """ Looks at the historical data of a particular test to investigate
    the reasons why it fails an the frequency """

    print("Summary:")
    print("\tLooking for failures of test {}/{}".format(test_name,
                                                          test_title))
    print("\ton the last {} failed tests".format(HISTORY_LEN))


    job_name = "system_tests_splitgpg"
    jobs = OpenQA.get_latest_job_ids(job_name, version="4.1",
                                     n=HISTORY_LEN, result="failed")


    for job_id in jobs:

        job = JobData(job_id)
        result = job.get_results()
        test_failures = result[job_name]

        print("\n# Job {} (from {})".format(job_id, job.get_job_start_time()))

        for test_failure in test_failures:
            if test_name == test_failure.name:

                if not test_title:
                    print("\n## {}".format(test_failure.title))
                    print("```python")
                    print(test_failure)
                    print("```")
                elif test_title == test_failure.title:
                    print("```python")
                    print(test_failure)
                    print("```")



def main():
    parser = ArgumentParser(
        description="Look for unstable tests")

    parser.add_argument(
        "--test",
        help="Test Case (e.g.: TC_00_Direct_debian-10/test_000_version)")

    parser.add_argument(
        '--build',
        help="Requires --latest. System build to look for, "
             "for example 4.0-20190801.1.")
    parser.add_argument(
        '--version',
        help="Requires --latest. System version to look for, for example 4.1.")

    args = parser.parse_args()

    try:
        (test_name, test_title) = args.test.split('/')
    except ValueError:
        test_name = args.test
        test_title = None

    if args.test:
        historical_test_failures(test_name, test_title)


if __name__ == '__main__':
    main()
