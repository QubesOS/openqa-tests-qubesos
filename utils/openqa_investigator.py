from github_reporting import OpenQA, JobData, TestFailure
from argparse import ArgumentParser
import textwrap
from copy import deepcopy
import re
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import logging

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

    if len(job_ids) == 0:
        print("ERROR: no jobs found. Wrong test suite name?")

    for job_id in job_ids:
        yield JobData(job_id)

def report_test_failure(job, test_name, test_title, outdir):
    """
    Prints the failures of a particular test pattern
    """

    result = job.get_results()
    test_failures = result[job.get_job_name()]
    report = ""

    if test_failures:
        report = "\n## Job {} (flavor '{}' from {})\n".format(job.job_id,
                                                    job.get_job_flavor(),
                                                    job.get_job_start_time())
    for test_failure in test_failures:
        if not test_title == test_failure.title: # regex title
            report += "\n\n### [{}/{}]({})\n".format(
                test_failure.name,
                test_failure.title,
                test_failure.get_test_url())
        report += "```python\n"
        report += str(test_failure.error_message)
        report += "\n```\n"

    return report

def report_summary_tests(jobs, test_suite, outdir=None):
    report = ""
    report += report_table_tests(jobs, outdir)

    plot_title = "errors by time"
    if outdir:
        plot_filename = "{}_{}.png".format(test_suite, "tests")
        plot_filepath = "{}/{}".format(outdir, plot_filename)
        plot_group_by_test(plot_title, jobs, test_suite, plot_filepath)
        report += "\n\n"
        report += "![]({})".format(plot_filepath)
    else:
        plot_group_by_test(plot_title, jobs, test_suite)

    return report

def report_summary_templates(jobs, test_suite, outdir=None):

    report = ""
    report += report_table_templates(jobs, outdir)

    plot_title = "errors by time"
    if outdir:
        plot_filename = "{}_{}.png".format(test_suite, "tests")
        plot_filepath = "{}/{}".format(outdir, plot_filename)
        plot_group_by_template(plot_title, jobs, test_suite, plot_filepath)
        report += "\n\n"
        report += "![]({})".format(plot_filepath)
    else:
        plot_group_by_template(plot_title, jobs, test_suite)

    return report

def report_summary_errors(jobs, test_suite, outdir=None):

    report = ""
    report += report_table_errors(jobs, outdir)

    plot_title = "errors by time"
    if outdir:
        plot_filename = "{}_{}.png".format(test_suite, "tests")
        plot_filepath = "{}/{}".format(outdir, plot_filename)
        plot_group_by_error(plot_title, jobs, test_suite, plot_filepath)
        report += "\n\n"
        report += "![]({})".format(plot_filepath)
    else:
        plot_group_by_error(plot_title, jobs, test_suite)

    return report

def report_table_tests(jobs, outdir):
    results = report_get_dict_tests(jobs, outdir)
    return report_format_table(results, "test name")

def report_table_templates(jobs, outdir):
    results = report_get_dict_templates(jobs, outdir)
    return report_format_table(results, "template name")

def report_table_errors(jobs, outdir):
    results = report_get_dict_errors(jobs, outdir)
    return report_format_table(results, "error message")

def report_get_dict_tests(jobs, outdir):
    group_by_fn = lambda test: test.name
    return report_get_dict(jobs, group_by_fn, outdir)

def report_get_dict_templates(jobs, outdir):
    group_by_fn = lambda test: test.title
    return report_get_dict(jobs, group_by_fn, outdir)

def report_get_dict_errors(jobs, outdir):
    group_by_fn = lambda test: group_by_error(test).replace("\n", "\\n")
    return report_get_dict(jobs, group_by_fn, outdir)

def report_get_dict(jobs, group_by_fn, outdir):
    result = {}

    for job in jobs:
        results = job.get_results()[job.get_job_name()]
        for test in results:
            group = group_by_fn(test)
            if group in result.keys():
                result[group] += 1
            else:
                result[group] = 1

    return result

def report_format_table(dict, title):
    longest_group_len = max(map(len, dict.keys()))
    pad = longest_group_len + 1
    pad_header = " "*(int((pad - len(title))/2))
    report  = "\n"
    report += "| count | {}{}{}|\n".format(pad_header, title, pad_header)
    report += "|-------|-{}|\n".format("-"*pad)

    for group in dict.keys():
        count = dict[group]
        count_pad = " "*(6-len(str(count)))
        group_pad = " "*(pad-len(group))
        report +="| {}{}| {}{}|\n".format(count, count_pad, group, group_pad)

    return report

def filter_valid_job(job):
    return job.is_valid()

def filter_tests_by_name(job, test_name, test_title):
    """
    Filters out tests that don't match a particular test pattern
    """
    results = job.get_results()
    test_failures = results[job.get_job_name()]

    filtered_results = []

    for test_failure in test_failures:
        if test_matches(test_failure.name, test_name,\
                        test_failure.title, test_title):
            filtered_results.append(test_failure)

    filtered_job = deepcopy(job)
    filtered_job.failures[job.get_job_name()] = filtered_results

    return filtered_job

def filter_tests_by_error(job, error_pattern):
    """
    Filters through tests that have a certain error message pattern
    """
    results = job.get_results()
    test_failures = results[job.get_job_name()]

    filtered_results = []

    for test_failure in test_failures:
        if test_failure.error_message and \
            re.search(error_pattern, test_failure.error_message):
            filtered_results.append(test_failure)

    filtered_job = deepcopy(job)
    filtered_job.failures[job.get_job_name()] = filtered_results

    return filtered_job

def group_by_error(test):
    if not test.error_message:
        return "no error printed\n(probably a native openQA test)"

    desc_lines = test.error_message.split("\n")

    result = ""
    max_chars = 40

    # attempt to find the line with the relevant result
    for line in reversed(desc_lines):
        if any(map(lambda error: error in line, IGNORED_ERRORS)): # ignore certain
            continue
        elif line == "" or re.search("^\s+$", line): # whitespace
            continue
        else:
            if result: # last two lines
                result = line[:max_chars] + ".*\n" + result
                break
            else:
                result = line[:max_chars] + ".*"

    if result == "":
        return "ignored error"

    return result

def group_by_template(test):
    # obtain template name according to construction format of
    # https://github.com/QubesOS/qubes-core-admin/blob/f60334/qubes/tests/__init__.py#L1352
    # Will catch most common tests.
    template = test.name.split("_")[-1]
    template = template.split("-pool")[0] # remove trailing "-pool"

    if re.search(r"^[a-z\-]+\-\d+(\-xfce)?$", template): # [template]-[ver]
        return template
    else:
        msg  = "Test's name '{}' doesn't specify a template.\n".format(test.name)
        msg += "  The test suite may not include template information in the"
        msg += " test's name."
        logging.warning(msg)

        return "unspecifed template"

def plot_group_by_test(title, jobs, test_suite, outfile=None):
    y_fn = lambda test: test.title
    plot_simple(title, jobs, test_suite, y_fn, outfile)

def plot_group_by_template(title, jobs, test_suite, outfile=None):
    plot_simple(title, jobs, test_suite, group_by_template, outfile)

    def group_by_template(test):
        # obtain template name according to construction format of
        # https://github.com/QubesOS/qubes-core-admin/blob/f60334/qubes/tests/__init__.py#L1352
        # Will catch most common tests.
        template = test.name.split("_")[-1]
        template = template.split("-pool")[0] # remove trailing "-pool"

        if re.search(r"^[a-z\-]+\-\d+(\-xfce)?$", template): # [template]-[ver]
            return template

        msg  = "Test's name '{}' doesn't specify a template.\n".format(test.name)
        msg += "  The test suite '{}' may not include".format(test_suite)
        msg += "template information in the test's name."
        raise Exception(msg)

    plot_simple(title, jobs, test_suite, group_by_template, outfile)

def plot_group_by_worker(title, jobs, test_suite, outfile):

    def group_by(test):
        job = JobData(test.job_id)
        return job.get_job_details()['job']['assigned_worker_id']

    plot_simple(title, jobs, test_suite, group_by, outfile)

def plot_group_by_error(title, jobs, test_suite, outfile=None):
    hue_fn=group_by_template
    plot_strip(title, jobs, test_suite, group_by_error, hue_fn, outfile)

def plot_simple(title, jobs, test_suite, y_fn, outfile=None):
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

    plt.figure(figsize=(10,7))

    groups = set()
    for job in jobs:
        results = job.get_results()[job.get_job_name()]
        for test in results:
            groups.add(y_fn(test))

    # initialize data
    y_data = {}
    for test in sorted(groups):
        y_data[test] = [0]*len(jobs)

    for i, job in enumerate(jobs):
        results = job.get_results()[job.get_job_name()]
        for test in results:
            y_data[y_fn(test)][i] += 1

    x_data = list(map(lambda job: str(job.get_job_parent()), jobs))

    # sort the data by number of failed tests so it the one with the most
    # failures shows at the top of the legend
    y_data = dict(sorted(y_data.items(), key=lambda entry: sum(entry[1]),
                       reverse=True))

    with plt.style.context('Solarize_Light2'):
        for key in y_data.keys():
            plt.xticks(rotation=70)
            plt.plot(x_data, y_data[key], label=key, linewidth=2)

    plt.title(title)
    plt.xlabel('parent job')
    plt.ylabel('times test failed')
    plt.legend()

    if outfile:
        file_path = outfile
        plt.savefig(file_path)
        print("plot saved at {}".format(file_path))
    else:
        plt.show()

def plot_strip(title, jobs, test_suite, y_fn, hue_fn, outfile=None):
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
    plt.figure(figsize=(14,7))
    plt.subplots_adjust(left = 0.03, right = 0.80)

    x_data = []
    y_data = []
    z_data = []

    for job in jobs:
        results = job.get_results()[job.job_name]
        for test in results:
            x_data += [str(job.job_id)]
            y_data += [y_fn(test)]
            z_data += [hue_fn(test)]

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

    plt.title(title)
    plt.xlabel('job')
    plt.ylabel('times test failed')
    plt.legend(loc="center left")

    if outfile:
        file_path = outfile
        plt.savefig(file_path)
        print("plot saved at {}".format(file_path))
    else:
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
        help="Select output format (report/plot_error/plot_templates/plot_tests)")

    parser.add_argument(
        "--outdir",
        help="path to save results")

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

    # remove invalid jobs
    jobs = filter(filter_valid_job, jobs)

    # apply filters
    if args.test:
        tests_filter = lambda job: filter_tests_by_name(job, test_name,
                                                        test_title)
        jobs = map(tests_filter, jobs)
        summary += "- tests matching: {}/{}\n".format(test_name, test_title)

    if args.error:
        tests_filter = lambda job: filter_tests_by_error(job, args.error)
        jobs = map(tests_filter, jobs)
        summary += "- error matches: {}\n".format(args.error)

    # output format
    report = ""

    # accumulate jobs for outputs that don't support generators
    if args.output not in ["report"]:
        jobs = list(jobs)
        plot_filepath = args.outdir+"plot.png" if args.outdir else None

    if args.output == "report":
        for job in jobs:
            report += report_test_failure(job, test_name, test_title,
                                          args.outdir)
    elif args.output == "plot_tests":
        title = "Failure By Test\n" + summary
        plot_group_by_test(title, jobs, args.suite, plot_filepath)
    elif args.output == "plot_templates":
        title = "Failure By Template\n" + summary
        plot_group_by_template(title, jobs, args.suite, plot_filepath)
    elif args.output == "plot_errors":
        title = "Failure By Error\n" + summary
        plot_group_by_error(title, jobs, args.suite, plot_filepath)
    elif args.output == "plot_worker":
        title = "Failure By Worker\n" + summary
        plot_group_by_worker(title, jobs, args.suite, plot_filepath)

    elif args.output == "table_tests":
        report += report_table_tests(jobs, args.outdir)
    elif args.output == "table_templates":
        report += report_table_templates(jobs, args.outdir)
    elif args.output == "table_errors":
        report += report_table_errors(jobs, args.outdir)

    elif args.output == "summary_tests":
        report += report_summary_tests(jobs, args.suite, args.outdir)
    elif args.output == "summary_templates":
        report += report_summary_templates(jobs, args.suite, args.outdir)
    elif args.output == "summary_errors":
        report += report_summary_errors(jobs, args.suite, args.outdir)
    else:
        print("Error: '{}' is not a valid output format".format(args.output))

    if args.outdir:
        file_path = args.outdir + "report.md"
        with open(file_path, 'w') as f:
            f.write(report)
        print("report saved at {}".format(file_path))
    else:
        print(report)

if __name__ == '__main__':
    main()
