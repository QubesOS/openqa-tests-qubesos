from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from fnmatch import fnmatch
from copy import deepcopy
import re

import requests_cache
requests_cache.install_cache('openqa_cache', backend='sqlite', expire_after=8200)


Q_VERSION = "4.1"
FLAVOR = "pull-requests"

def get_jobs(test_suite, history_len):
    """
    Gets the historical data of a particular of job failures
    """

    jobs = OpenQA.get_latest_job_ids(test_suite, version=Q_VERSION,
                                     history_len=history_len, result="failed",
                                     flavor=FLAVOR)

    for job_id in jobs:
        yield JobData(job_id)

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
        if not test_title == test_failure.title: # wildcard title
            print("\n### {}".format(test_failure.title))

        print("```python")
        print(test_failure)
        print("```")

def filter_tests(job, test_suite, test_name, test_title):
    """
    Filters out tests that don't match a particular test pattern
    """
    results = job.get_results()
    test_failures = results[test_suite]

    filtered_results = []

    for test_failure in test_failures:
        if test_matches(test_failure.name, test_name,\
                        test_failure.title, test_title):
            filtered_results.append(test_failure)

    filtered_job = deepcopy(job)
    filtered_job.failures[job.get_job_name()] = filtered_results

    return filtered_job

def filter_tests_by_error(job, test_suite, error_pattern):
    """
    Filters through tests that have a certain error message pattern
    """
    results = job.get_results()
    test_failures = results[test_suite]

    filtered_results = []

    for test_failure in test_failures:
        if test_failure.description and \
            re.search(error_pattern, test_failure.description):
            filtered_results.append(test_failure)

    filtered_job = deepcopy(job)
    filtered_job.failures[job.get_job_name()] = filtered_results

    return filtered_job

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
        help="Test Case with wildcard support (include \"\")"
             "(e.g.: \"TC_00_Direct_*/test_000_version)\"")

    parser.add_argument(
        "--error",
        help="Match only results with a specific error message"
             "(e.g.: \"dogtail.tree.SearchError: descendent of [file chooser\"")

    parser.add_argument(
        "--last",
        nargs='?',
        help="Last N failed tests"
                "(e.g.: 100)")

    args = parser.parse_args()

    try:
        (test_name, test_title) = args.test.split('/')
    except ValueError:
        test_name = args.test
        test_title = "*"

    if not args.last:
        history_len = 100
    else:
        try:
            history_len = int(args.last)
        except ValueError:
            print("Error: {} is not a valid number".format(args.last))
            exit(1)


    print("Summary:")
    print("\tLooking for failures of test {}/{}".format(test_name,
                                                        test_title))
    print("\ton the last {} failed tests".format(history_len))
    print("\nsuite: ", args.suite)

    jobs = get_jobs(args.suite, history_len)

    if args.test:
        tests_filter = lambda job: filter_tests(job, args.suite,
                                            test_name, test_title)
        jobs = map(tests_filter, jobs)

    if args.error:
        tests_filter = lambda job: filter_tests_by_error(job, args.suite,\
                                                         args.error)
        jobs = map(tests_filter, jobs)

    for job in jobs:
        print_test_failure(job, args.suite, test_name, test_title)


if __name__ == '__main__':
    main()
