from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from copy import deepcopy
import re
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd

import requests_cache
requests_cache.install_cache('openqa_cache', backend='sqlite', expire_after=8200)


Q_VERSION = "4.1"
FLAVOR = "pull-requests"
IGNORED_ERRORS = [
    "# system-out:",
    "# Result:",
    "# wait_serial expected",
    "0;31m"
]

def get_jobs(test_suite, history_len):
    """
    Gets the historical data of a particular test suite
    """

    success_jobs = OpenQA.get_latest_job_ids(test_suite, version=Q_VERSION,
                                     result="passed",  history_len=history_len,
                                     flavor=FLAVOR)

    failed_jobs = OpenQA.get_latest_job_ids(test_suite, version=Q_VERSION,
                                        result="failed",
                                        history_len=history_len, flavor=FLAVOR)

    job_ids = sorted(success_jobs + failed_jobs)
    job_ids = job_ids[-history_len:]

    for job_id in job_ids:
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

def plot_group_by_test(title, jobs, test_suite):
    plot_simple(title, jobs, test_suite, y_fn=lambda test: test.title)

def plot_group_by_template(title, jobs, test_suite):
    plot_simple(title, jobs, test_suite, y_fn=lambda test: test.name)

def plot_group_by_error(title, jobs, test_suite):

    def group_by_error(test):
        if not test.description:
            return "no error printed\n(probably a native openQA test)"

        desc_lines = test.description.split("\n")

        result = ""
        max_chars = 22

        # attempt to find the line with the relevant result
        for line in reversed(desc_lines):
            if any(map(lambda error: error in line, IGNORED_ERRORS)): # ignore certain
                continue
            elif line == "" or re.search("^\s+$", line): # whitespace
                continue
            else:
                if result: # last two lines
                    result = line[:max_chars] + "...\n" + result
                    break
                else:
                    result = line[:max_chars] + "..."

        if result == "":
            return "ignored error"

        return result

    plot_strip(title, jobs, test_suite,
               y_fn=group_by_error,
               hue_fn=lambda test: test.name)

def plot_simple(title, jobs, test_suite, y_fn):
    """Plots test results with simple plotting where (x=job, y=y_fn)

      ^ (y_fn)
      |        .
      |       / \
      |   ___/   \
      |  /        \       /\
      | /          \_____/  \___
      +---------------------------> (job)

    Args:
        title (list): title and subtitle of the test.
        jobs (list): a list of all the JobData.
        test_suite (str): test suite.
        y_fn (function(TestFailure)): function to group the results by.
    """

    valid_jobs = set() # jobs with valid results
    groups = set()
    for job in jobs:
        results = job.get_results()[test_suite]
        for test in results:
            groups.add(y_fn(test))
            valid_jobs.add(job)

    # initialize data
    x_data = []
    y_data = {}
    for test in sorted(groups):
        y_data[test] = [0]*len(valid_jobs)

    for i, job in enumerate(valid_jobs):
        results = job.get_results()[test_suite]
        x_data.append(job.job_id)
        for test in results:
            y_data[y_fn(test)][i] += 1

    x_data = sorted(x_data)
    x_data = list(map(str, x_data))

    # sort the data by number of failed tests so it the one with the most
    # failures shows at the top of the legend
    y_data = dict(sorted(y_data.items(), key=lambda entry: sum(entry[1]),
                       reverse=True))

    with plt.style.context('Solarize_Light2'):
        for key in y_data.keys():
            plt.xticks(rotation=70)
            plt.plot(x_data, y_data[key], label=key, linewidth=2)

    plt.title(title[1])
    plt.suptitle(title[0])
    plt.xlabel('job')
    plt.ylabel('times test failed')
    plt.legend()
    plt.show()

def plot_strip(title, jobs, test_suite, y_fn, hue_fn):
    """ Plots tests's failures along the jobs axis. Good for telling the
    evolution of a test's failure along time.
    (x=job, y=y_fn, hue=hue_fn)

               ^ (y_fn)
      group 1 -|        .       .        . (hue=hue_fn)
      group 2 -|  ...... .... ...... .....
      group 3 -|
      group 4 -|     .  .      .     .   .
      group 5 -| ..       ....    ..   .
               +---------------------------> (job)

    Args:
        title (list): title and subtitle of the test.
        jobs (list): a list of all the JobData.
        test_suite (str): test suite.
        y_fn (function(TestFailure)): function to group the results by.
        hue_fn (function(TestFailure)): function to color the results by.
    """

    x_data = []
    y_data = []
    z_data = []

    for job in jobs:
        results = job.get_results()[test_suite]
        for test in results:
            x_data.append((str(job.job_id)))
            y_data.append(y_fn(test))
            z_data.append(hue_fn(test))

    hue_palette = sns.color_palette("tab20", n_colors=len(set(z_data)))
    tests_palette = ["#ff6c6b", # alternate through 3 colors to be able to tell
                     "#fea032", # consecutive Y values appart
                     "#4fa1ed"]

    job_ids = [job.job_id for job in jobs]
    job_ids_str = list(map(str, job_ids))

    df = pd.DataFrame({# x is categorical to also show job_ids when successful
                       "x": pd.Categorical(x_data, categories=job_ids_str),
                       "y": y_data,
                       # z is categorical to order the legend
                       "z": pd.Categorical(z_data, ordered=True,
                                           categories=sorted(set(z_data)))})

    # NOTE: plotting the "hue" significantly slows down the plotting
    sns.stripplot(x="x", y="y", hue="z", data=df, jitter=0.2, orient="v",
                  palette=hue_palette)
    plt.xticks(rotation=70)

    # apply palette and hlines to Y labels so it's easier to identify them
    axis = plt.gca()
    axis.yaxis.tick_right()
    for i, tick in enumerate(axis.get_yticklabels()):
        color = tests_palette[i%3]
        tick.set_color(color)
        tick.set_fontsize(8)
        plt.axhline(y = i, linewidth=0.3, color = color, linestyle = '-')

    plt.title(title[1])
    plt.suptitle(title[0])
    plt.xlabel('job')
    plt.ylabel('times test failed')
    plt.legend()
    plt.show()

def test_matches(test_name, test_name_pattern, test_title, test_title_pattern):
    try:
        return test_name_matches(test_name, test_name_pattern) and \
            test_title_matches(test_title, test_title_pattern)
    except re.error:
        raise Exception("Error: \"{}/{}\" is not a valid regex".\
            format(test_name_pattern, test_title_pattern))

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
        help="Select output format (markdown/plot_error/plot_templates/plot_tests)")

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

    jobs = get_jobs(args.suite, history_len)
    summary = "- suite: {}".format(args.suite)


    # apply filters
    if args.test:
        tests_filter = lambda job: filter_tests(job, args.suite,
                                            test_name, test_title)
        jobs = map(tests_filter, jobs)
        summary += "- tests matching: {}/{}\n".format(test_name, test_title)

    if args.error:
        tests_filter = lambda job: filter_tests_by_error(job, args.suite,\
                                                         args.error)
        jobs = map(tests_filter, jobs)
        summary += "- error matches: {}\n".format(args.error)

    # output format
    if args.output == "report":
        for job in jobs:
            print_test_failure(job, args.suite, test_name, test_title)
    elif args.output == "plot_tests":
        title = ["Failure By Test", summary]
        plot_group_by_test(title, list(jobs), args.suite)
    elif args.output == "plot_templates":
        title = ["Failure By Template", summary]
        plot_group_by_template(title, list(jobs), args.suite)
    elif args.output == "plot_errors":
        title = ["Failure By Error", summary]
        plot_group_by_error(title, list(jobs), args.suite)
    else:
        print("Error: '{}' is not a valid output format".format(args.output))

if __name__ == '__main__':
    main()
