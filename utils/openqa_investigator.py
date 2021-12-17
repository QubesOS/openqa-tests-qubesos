from argparse import ArgumentParser
import re
import os
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import logging
from sqlalchemy import or_

from lib.openqa_api import (
    setup_openqa_environ,
    get_db_session,
    JobData,
    TestFailure,
    OpenQA
)

DEFAULT_Q_VERSION = "4.1"
DEFAULT_FLAVOR = "pull-requests"

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
    hue_fn = lambda test: test.name
    plot_strip(title, jobs, failures_q, test_suite, y_fn, hue_fn, outfile)

def plot_by_template(title, jobs, failures_q, test_suite, outfile=None):
    group_by_template = lambda test: test.template
    plot_strip(title, jobs, failures_q, test_suite, group_by_template,
               outfile=outfile)

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
    y_fn = lambda test: str(test.job.worker)
    plot_strip(title, jobs, failures_q, test_suite, y_fn, outfile=outfile)

def plot_strip(title, jobs, failures_q, test_suite, y_fn, hue_fn=None,
               outfile=None):
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
    alternating_3_color_palette = ["#ff6c6b", "#fea032", "#4fa1ed"]

    x_data = []
    y_data = []
    z_data = []

    for job in jobs:
        job_test_failures = failures_q\
            .filter(TestFailure.job_id == job.job_id).all()
        for test in job_test_failures:
            x_data += [str(job.job_id)]
            y_data += [y_fn(test)]
            if hue_fn:
                z_data += [hue_fn(test)]

    job_ids = [job.job_id for job in jobs]
    job_ids_str = list(map(str, job_ids))

    data = {}
    # x is categorical to also show job_ids when successful
    data["x"] = pd.Categorical(x_data, categories=job_ids_str)
    data["y"] = y_data
    if hue_fn:
        # z is categorical to order the legend
        data["z"] = pd.Categorical(z_data, ordered=True,
                                categories=sorted(set(z_data)))
    df = pd.DataFrame(data)

    if hue_fn:
        # NOTE: plotting the "hue" significantly slows down the plotting
        hue_palette = sns.color_palette("tab20", n_colors=len(set(z_data)))
        sns.stripplot(x="x", y="y", hue="z", data=df, jitter=0.2, orient="v",
                  palette=hue_palette)
    else:
        sns.stripplot(x="x", y="y", hue="y", data=df, jitter=0.2, orient="v",
                      palette=alternating_3_color_palette)
    plt.xticks(rotation=70)

    # apply palette and hlines to Y labels so it's easier to identify them
    axis = plt.gca()
    axis.yaxis.tick_right()
    for i, tick in enumerate(axis.get_yticklabels()):
        color = alternating_3_color_palette[i%3]
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
        '--version',
        default=DEFAULT_Q_VERSION,
        help="Specify the Qubes version. "
                "Default: {}".format(DEFAULT_Q_VERSION))

    parser.add_argument(
        '--flavor',
        default=DEFAULT_FLAVOR,
        help="Specify the job's flavor / group. "
                "Default: {}".format(DEFAULT_FLAVOR))

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
        type=int,
        default=100,
        help="Last N failed tests"
                "(e.g.: 100)")

    parser.add_argument(
        "--output",
        help="Select output format (report/plot_error/plot_templates/plot_tests)")

    parser.add_argument(
        "--outdir",
        help="path to save results")

    parser.add_argument(
        '--verbose',
        action='store_true',
        help="Enable debug logging."
    )

    parser.set_defaults(output="report")
    args = parser.parse_args()

    base_dir = os.path.abspath(os.path.dirname(__file__))
    mapping_path = os.path.join(base_dir, "github_package_mapping.json")
    setup_openqa_environ(mapping_path, verbose=args.verbose)

    try:
        (test_name_regex, test_title_regex) = args.test.split('/')
    except ValueError:
        test_name_regex = args.test
        test_title_regex = "*"

    history_len = args.last
    history_len_with_margin = history_len*2 # account for invalid jobs

    # populate database
    db = get_db_session()
    concluded_job_ids = OpenQA.get_latest_concluded_job_ids(
        args.suite, history_len_with_margin,
        args.version, args.flavor)
    OpenQA.get_jobs(concluded_job_ids)

    jobs_reversed_query = db.query(JobData)\
            .filter(JobData.valid == True)\
            .filter(JobData.job_name == args.suite)\
            .filter(JobData.version == args.version)\
            .filter(JobData.flavor == args.flavor)\
            .where(JobData.job_id.in_(concluded_job_ids))\
            .order_by(JobData.job_id.desc())\
            .limit(history_len) # order_by in order to truncate the limit

    failures_q = db.query(TestFailure)\
                   .join(jobs_reversed_query.subquery())

    # apply filters
    if args.test:
        failures_q = failures_q\
            .filter(TestFailure.name.regexp_match(test_name_regex))\
            .filter(TestFailure.title.regexp_match(test_title_regex))

    if args.error:
        failures_q = failures_q.filter(or_(
                TestFailure.fail_error.regexp_match(args.error),
                TestFailure.cleanup_error.regexp_match(args.error)))

    jobs_reversed = jobs_reversed_query.all()
    jobs = reversed(jobs_reversed)

    # output format
    report = ""

    if args.output not in ["report"]:
        jobs = list(jobs)
        plot_filepath = args.outdir+"plot.png" if args.outdir else None
        if len(jobs) == 0:
            print("No jobs found")
            return

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
