from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from copy import deepcopy
import re
import matplotlib.pyplot as plt

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
        if not test_title == test_failure.title: # regex title
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

def plot_group_by_test(jobs, test_suite):
    plot(jobs, test_suite, lambda test: test.title)

def plot_group_by_template(jobs, test_suite):
    plot(jobs, test_suite, lambda test: test.name)

def plot(jobs, test_suite, group_by_fn):
    """Plots test results

    Args:
        jobs (list): a list of all the JobData.
        test_suite (str): test suite.
        group_by_fn (function(TestFailure)): function to group the results by.
    """

    groups = set()
    for job in jobs:
        results = job.get_results()[test_suite]
        for test in results:
            groups.add(group_by_fn(test))

    # initialize data
    data = {}
    for test in sorted(groups):
        data[test] = [0]*len(jobs)

    for i, job in enumerate(jobs):
        results = job.get_results()[test_suite]
        for test in results:
            data[group_by_fn(test)][i] += 1

    job_ids = [job.job_id for job in jobs]
    job_ids_str = list(map(str, job_ids))

    for key in data.keys():
        plt.xticks(rotation=70)
        plt.plot(job_ids_str, data[key], label=key, linewidth=2)

    plt.title('Failed tests per job')
    plt.xlabel('job')
    plt.ylabel('times test failed')
    plt.legend()
    plt.show()

def test_matches(test_name, test_name_pattern, test_title, test_title_pattern):
    try:
        return test_name_matches(test_name, test_name_pattern) and \
            test_title_matches(test_title, test_title_pattern)
    except re.error:
        print("Error: \"{}/{}\" is not a valid regex".format(test_name_pattern, test_title_pattern))

def test_name_matches(test_name, test_name_pattern):
    return re.search(test_name_pattern, test_name)

def test_title_matches(test_title, test_title_pattern):
    return re.search(test_title_pattern, test_title)

def main():
    parser = ArgumentParser(
        description="Look for unstable tests")

    parser.add_argument(
        "--suite",
        help="Test suite name"
             "(e.g.: system_tests_splitgpg)")

    parser.add_argument(
        "--test",
        help="Test Case with regex support (use inside \"\")"
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

    parser.add_argument(
        "--output",
        help="Select output format (markdown/plot)")

    parser.set_defaults(output="report")
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

    # apply filters
    if args.test:
        tests_filter = lambda job: filter_tests(job, args.suite,
                                            test_name, test_title)
        jobs = map(tests_filter, jobs)

    if args.error:
        tests_filter = lambda job: filter_tests_by_error(job, args.suite,\
                                                         args.error)
        jobs = map(tests_filter, jobs)

    # output format
    if args.output == "report":
        for job in jobs:
            print_test_failure(job, args.suite, test_name, test_title)
    elif args.output == "plot":
        if not re.match(r'\w+', test_title): # regex test
            plot_group_by_test(list(jobs), args.suite)
        else:                                # concrete test
            plot_group_by_template(list(jobs), args.suite)

if __name__ == '__main__':
    main()
