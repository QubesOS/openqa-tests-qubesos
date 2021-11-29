from argparse import ArgumentParser
import re
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import logging
from sqlalchemy import or_

from lib.openqa_api import (
    setup_openqa_environ,
    get_db_session,
    JobData,
    TestFailure
)
from lib.instability_analysis import get_latest_jobs

IGNORED_ERRORS = [
    "# system-out:",
    "# Result:",
    "# wait_serial expected",
    "0;31m"
]

def report_test_failure(job, test_failures):
    """
    Prints the failures of a particular test pattern
    """
    report = ""
    if test_failures:
        report = "\n## Job {} (flavor '{}' from {})\n".format(job.job_id,
                                                    job.get_job_flavor(),
                                                    job.get_job_start_time())
    for test_failure in test_failures:
        report += "### " + str(test_failure)
        if test_failure.fail_error:
            report += "\n\n**Failed with the following:**\n"
            report += "```python\n"
            report += str(test_failure.fail_error.strip())
            report += "\n```\n"
        if test_failure.cleanup_error:
            report += "**It had cleanup errors:**\n"
            report += "```python\n"
            report += str(test_failure.cleanup_error.strip())
            report += "\n```\n"

    return report

def plot_by_test(title, jobs, failures_q, test_suite, outfile=None):
    y_fn = lambda test: test.title
    plot_simple(title, jobs, failures_q, test_suite, y_fn, outfile)

def plot_by_template(title, jobs, failures_q, test_suite, outfile=None):
    group_by_template = lambda test: test.template
    plot_simple(title, jobs, failures_q, test_suite, group_by_template, outfile)

def plot_by_error(title, jobs, failures_q, test_suite, outfile=None):

    def group_by_error(test):
        if test.relevant_error:
            return test.relevant_error
        else:
            return "[empty error message]"

    group_by_template = lambda test: test.template
    plot_strip(title, jobs, failures_q, test_suite, group_by_error,
               hue_fn=group_by_template, outfile=outfile)

def plot_by_worker(title, jobs, failures_q, test_suite, outfile):
    y_fn = lambda test: test.job.worker
    plot_simple(title, jobs, failures_q, test_suite, y_fn, outfile)

def plot_simple(title, jobs, failures_q, test_suite, y_fn, outfile=None):
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

    # obtains the tes failures associated with each job
    results = {}
    for job in jobs:
        test_failures = failures_q\
            .filter(TestFailure.job_id == job.job_id).all()
        results[job] = test_failures

    groups = set()
    for job in jobs:
        for test in results[job]:
            groups.add(y_fn(test))

    # initialize data
    y_data = {}
    for test in sorted(groups):
        y_data[test] = [0]*len(jobs)

    for i, job in enumerate(jobs):
        for test in results[job]:
            y_data[y_fn(test)][i] += 1

    x_data = list(map(lambda job: str(job.parent_job_id), jobs))

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

def plot_strip(title, jobs, failures_q, test_suite, y_fn, hue_fn, outfile=None):
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
        job_test_failures = failures_q\
            .filter(TestFailure.job_id == job.job_id).all()
        for test in job_test_failures:
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
        help="Match only results with a specific error message regex"
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

    setup_openqa_environ("github_package_mapping.json") # remove hardcode

    try:
        (test_name_regex, test_title_regex) = args.test.split('/')
    except ValueError:
        test_name_regex = args.test
        test_title_regex = "*"

    if not args.last:
        history_len = 100
    else:
        try:
            history_len = int(args.last)
        except ValueError:
            print("Error: {} is not a valid number".format(args.last))
            exit(1)

    db = get_db_session()
    get_latest_jobs(db, args.suite, history_len)

    jobs_query = db.query(JobData)\
            .filter(JobData.valid == True)\
            .filter(JobData.job_name == args.suite)
    failures_q = db.query(TestFailure)\
                   .join(jobs_query.subquery())

    # apply filters
    if args.test:
        failures_q = failures_q\
            .filter(TestFailure.name.regexp_match(test_name_regex))\
            .filter(TestFailure.title.regexp_match(test_title_regex))

    if args.error:
        failures_q = failures_q.filter(or_(
                TestFailure.fail_error.regexp_match(args.error),
                TestFailure.cleanup_error.regexp_match(args.error)))

    jobs = jobs_query.all()

    # output format
    report = ""

    if args.output not in ["report"]:
        jobs = list(jobs)
        plot_filepath = args.outdir+"plot.png" if args.outdir else None

    if args.output == "report":
        for job in jobs:
            test_failures = failures_q\
                .filter(TestFailure.job_id == job.job_id).all()
            report += report_test_failure(job, test_failures)

    elif args.output == "plot_tests":
        title = "Failure By Test\n"
        plot_by_test(title, jobs, failures_q, args.suite, plot_filepath)
    elif args.output == "plot_templates":
        title = "Failure By Template\n"
        plot_by_template(title, jobs, failures_q, args.suite, plot_filepath)
    elif args.output == "plot_errors":
        title = "Failure By Error\n"
        plot_by_error(title, jobs, failures_q, args.suite, plot_filepath)
    elif args.output == "plot_worker":
        title = "Failure By Worker\n"
        plot_by_worker(title, jobs, failures_q, args.suite, plot_filepath)

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
