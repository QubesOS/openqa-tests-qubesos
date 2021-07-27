from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from fnmatch import fnmatch

HISTORY_LEN = 200
Q_VERSION = "4.1"
FLAVOR = "pull-requests"

def print_tests_failures(test_suite, test_name, test_title):
    """
    Prints the historical data of a particular of job failures for a
    particular test pattern
    """

    print("Summary:")
    print("\tLooking for failures of test {}/{}".format(test_name,
                                                          test_title))
    print("\ton the last {} failed tests".format(HISTORY_LEN))
    print("\nsuite: ", test_suite)

    jobs = OpenQA.get_latest_job_ids(test_suite, version=Q_VERSION,
                                     n=HISTORY_LEN, result="failed",
                                     flavor=FLAVOR)

    for job_id in jobs:
        job = JobData(job_id)
        print_test_failure(job, test_suite, test_name, test_title)

def print_test_failure(job, test_suite, test_name, test_title):
    """
    Prints the failures of a particular test pattern
    """

    result = job.get_results()
    test_failures = result[test_suite]

    print("\n## Job {} (flavor '{}' from {})".format(job.job_id,
                                                    job.get_job_flavor(),
                                                    job.get_job_start_time()))

    for test_failure in test_failures:
        if test_matches(test_failure.name, test_name,\
                        test_failure.title, test_title):

            if not test_title == test_failure.title: # wildcard title
                print("\n### {}".format(test_failure.title))

            print("```python")
            print(test_failure)
            print("```")
        else:
            print("Warning: no matches for {}/{}".format(test_name, test_title))

def test_matches(test_name, test_name_pattern, test_title, test_title_pattern):
    return test_name_matches(test_name, test_name_pattern) and \
           test_title_matches(test_title, test_title_pattern)

def test_name_matches(test_name, test_name_pattern):
    return fnmatch(test_name, test_name_pattern)

def test_title_matches(test_title, test_title_pattern):
    return fnmatch(test_title, test_title_pattern)

def main():
    parser = ArgumentParser(
        description="Look for unstable tests")

    parser.add_argument(
        "--suite",
        help="Test suite name"
             "(e.g.: system_tests_splitgpg)")

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
        print_tests_failures(args.suite, test_name, test_title)


if __name__ == '__main__':
    main()
