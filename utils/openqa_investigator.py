from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from fnmatch import fnmatch

HISTORY_LEN = 200
Q_VERSION = "4.1"
TEST_SUITE_NAME = "system_tests_network_ipv6"
FLAVOR = "pull-requests"

def historical_test_failures(test_name, test_title):
    """ Looks at the historical data of a particular test to investigate
    the reasons why it fails an the frequency """

    print("Summary:")
    print("\tLooking for failures of test {}/{}".format(test_name,
                                                          test_title))
    print("\ton the last {} failed tests".format(HISTORY_LEN))

    jobs = OpenQA.get_latest_job_ids(TEST_SUITE_NAME, version=Q_VERSION,
                                     n=HISTORY_LEN, result="failed",
                                     flavor=FLAVOR)

    for job_id in jobs:

        job = JobData(job_id)
        result = job.get_results()
        test_failures = result[TEST_SUITE_NAME]

        print("\n## Job {} (flavor '{}' from {})".format(job_id,
                                                      job.get_job_flavor(),
                                                      job.get_job_start_time()))

        for test_failure in test_failures:
            if fnmatch(test_failure.name, test_name):
                if fnmatch(test_failure.title, test_title):

                    if test_title != test_failure.title: # wildcard title
                        print("\n### {}".format(test_failure.title))

                    print("```python")
                    print(test_failure)
                    print("```")

def main():
    parser = ArgumentParser(
        description="Look for unstable tests")

    parser.add_argument(
        "--test",
        help="Test Case with wildcard support"
             "(e.g.: TC_00_Direct_*/test_000_version)")

    args = parser.parse_args()

    try:
        (test_name, test_title) = args.test.split('/')
    except ValueError:
        test_name = args.test
        test_title = "*"

    if args.test:
        historical_test_failures(test_name, test_title)


if __name__ == '__main__':
    main()
