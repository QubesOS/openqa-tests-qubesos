import json

import requests
from argparse import ArgumentParser
import re
import os

from lib.github_api import setup_github_environ, GitHubIssue, get_labels_from_results
from lib.openqa_api import setup_openqa_environ, OpenQA
from lib.instability_analysis import InstabilityAnalysis
from lib.common import ISSUE_TITLE_PREFIX, COMMENT_TITLE

def setup_environ(args):
    setup_github_environ(args.auth_token)
    setup_openqa_environ(args.package_list, args.db_path, verbose=args.verbose)

def fill_results_context(results, jobs, reference_jobs=None, instability_analysis=None):
    if reference_jobs:
        reference_job_results = {}
        for job in reference_jobs:
            reference_job_results.update(job.get_results())

        for k in results:
            current_fails = results[k]
            old_fails = reference_job_results.get(k, [])

            for fail in old_fails:
                if fail in current_fails:
                    continue
                fail.fixed = True
                current_fails.append(fail)

            for fail in current_fails:
                if fail not in old_fails:
                    fail.regression = True

    if instability_analysis is not None:
        for k in results.values():
            for fail in k:
                if instability_analysis.is_test_unstable(fail):
                    fail.unstable = True

def format_github_link(link):
    """
    Github "helpfully" formats links by removing information from it, try to prevent that
    """
    if '/commits/' in link:
        return link.partition('/commits/')[0] + f" ({link})"
    return link


def format_results(results, jobs, reference_jobs=None, instability_analysis=None, github_links=None):

    output_string = "{}\n" \
                    "Complete test suite and dependencies: {}\n".format(
                        COMMENT_TITLE,
                        jobs[0].get_build_url())

    if github_links and not ('create-or-update' in next(iter(github_links))):
        output_string += "\nTest run included the following:\n"
        output_string += ''.join(f"- {format_github_link(url)}\n" for url in github_links)

    if results.get('system_tests_update', []):
        output_string += "\nInstalling updates failed, skipping the report!\n"
        return output_string

    output_string += "\n"
    failed_tests_details = ""
    upload_failures = []
    for k in results:
        if results[k]:
            if all(f.fixed for f in results[k]):
                continue
            if any(f.name != "system_tests" for f in results[k]):
                continue
            failed_tests_details += '* ' + str(k) + "\n"
            for fail in results[k]:
                failed_tests_details += '  * ' + str(fail) + '\n'
                upload_failures.append(fail)
    if upload_failures:
        output_string +=  "## Upload failures\n"
        output_string += failed_tests_details

    if reference_jobs:
        output_string += "## New failures{}\n" \
                            "Compared to: {}\n".format(
                            ", excluding unstable" if instability_analysis else "",
                            reference_jobs[0].get_build_url())

        for k in results:
            fails = results[k]
            add_to_output = ""
            for fail in fails:
                if fail in upload_failures:
                    continue
                if fail.regression and not fail.unstable:
                    add_to_output += '  * ' + str(fail) + '\n'

            if add_to_output:
                output_string += '* ' + str(k) + "\n"
                output_string += add_to_output

    output_string +=  "## Failed tests\n"
    failed_tests_details = ""
    number_of_failures = 0
    for k in results:
        if results[k]:
            if all(f.fixed for f in results[k]):
                continue
            add_to_output = ""
            for fail in results[k]:
                if fail.fixed or fail in upload_failures:
                    continue
                if fail.unstable:
                    add_to_output += '  * [unstable] ' + str(fail) + '\n'
                else:
                    add_to_output += '  * ' + str(fail) + '\n'
                number_of_failures += 1
            if add_to_output:
                failed_tests_details += '* ' + str(k) + "\n"
                failed_tests_details += add_to_output

    if not number_of_failures:
        output_string += "No failures!\n"
    else:
        output_string += "<details><summary>{} failures</summary>\n\n{}</details>\n\n".format(
            number_of_failures, failed_tests_details)

    if reference_jobs:
        output_string += "## Fixed failures\n" \
                            "Compared to: {}\n".format(
                            reference_jobs[0].get_dependency_url())

        number_of_fixed = 0
        fixed_details = ""
        for k in results:
            fails = results.get(k, [])

            add_to_output = ""
            for fail in fails:
                if fail.fixed:
                    add_to_output += '  * ' + str(fail) + '\n'
                    number_of_fixed += 1

            if add_to_output:
                fixed_details += '* ' + str(k) + "\n"
                fixed_details += add_to_output
        if not number_of_fixed:
            output_string += "Nothing fixed\n"
        else:
            output_string += "<details><summary>{} fixed</summary>\n\n{}</details>\n\n".format(
                number_of_fixed, fixed_details)

    if instability_analysis:
        output_string += "## Unstable tests\n"
        output_string += instability_analysis.report(details=True)

    # performance tests
    output_string += "## Performance Tests\n\n"

    current_job_perf_data = {}
    ref_job_perf_data = {}
    for job in jobs:
        if job.job_name.endswith("perf"):
            current_job_perf_data[job.job_name] = job.get_performance_data()

    if reference_jobs:
        for job in reference_jobs:
            if job.job_name.endswith("perf"):
                ref_job_perf_data[job.job_name] = job.get_performance_data()

        performance_issues = []
        other_perf = []

        for job_name, test_results in current_job_perf_data.items():
            for test_name, result in test_results.items():
                s = f'* {test_name}: {result:.2f}'

                # try to find reference value
                ref = None
                if job_name in ref_job_perf_data:
                    ref = ref_job_perf_data[job_name].get(test_name, None)

                degradation = False
                alert = None

                if ref:
                    if 'qrexec' in job_name or 'dispvm' in job_name:
                        degradation = result / ref > 1
                        alert = result / ref > 1.1
                    else:
                        # a storage bandwidth job
                        degradation = result / ref < 1
                        alert = result / ref < 0.9

                if degradation:
                    red_triangle = "🔻"
                    s += (f" {red_triangle} ( previous "
                          f"job: {ref:.2f}, degradation: "
                          f"{result / ref:.2%})\n")
                elif ref:
                    green_circle = "🟢"
                    s += (f" {green_circle} ( previous "
                          f"job: {ref:.2f}, improvement: "
                          f"{result / ref:.2%})\n")
                else:
                    s += '\n'

                if alert:
                    performance_issues.append(s)
                else:
                    other_perf.append(s)

        output_string += "### Performance degradation:\n\n"
        if performance_issues:
            output_string += (
                ("<details><summary>{} performance degradations</summary>\n"
                 "\n{}</details>\n\n").format(
                len(performance_issues), "".join(performance_issues)))
        else:
            output_string += "No issues\n"

        output_string += "### Remaining performance tests:\n\n"
        if other_perf:
            output_string += (
                ("<details><summary>{} tests</summary>\n"
                 "\n{}</details>\n\n").format(
                len(other_perf), "".join(other_perf)))
        else:
            output_string += "No remaining performance tests\n"

    else:
        performance_tests = []
        for job_name, test_results in current_job_perf_data.items():
            for test_name, result in test_results.items():
                s = f'* {test_name}: {result:.2f}\n'
                performance_tests.append(s)

        output_string += ("<details><summary>{} tests</summary>\n\n{}</details>"
                          "\n\n").format(len(performance_tests),
                                         "".join(performance_tests))

    return output_string

def main():
    parser = ArgumentParser(
        description="Update GitHub issues with test reporting")

    parser.add_argument(
        "--auth-token",
        help="Github authentication token (OAuth2). If omitted, uses"
             " environment variable GITHUB_API_KEY")

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--job-id",
        type=int,
        help="Update all pull requests related to a given job id")
    group.add_argument(
        '--latest',
        action='store_true',
        help="Find the latest job with optional constraints.")

    parser.add_argument(
        '--job-name',
        default="system_tests_update",
        help="Requires --latest. Name of test job. "
             "Default: system_tests_update")

    parser.add_argument(
        '--flavor',
        default="update",
        help="Requires --latest. Flavor name. "
             "Default: update")

    parser.add_argument(
        '--build',
        help="Requires --latest. System build to look for, "
             "for example 4.0-20190801.1.")

    parser.add_argument(
        '--version',
        help="Requires --latest. System version to look for, for example 4.1.")

    parser.add_argument(
        '--package-list',
        required=True,
        help="A .json file containing mapping from distribution package names"
             "to Qubes repos.")

    parser.add_argument(
        '--show-results-only',
        action='store_true',
        help="Do not post to GitHub, only display test results in the console."
    )

    parser.add_argument(
        '--show-github-issues-only',
        action='store_true',
        help="Do not post to github, only display found related github issues"
    )

    parser.add_argument(
        '--enable-labels',
        action='store_true',
        help="Enable adding openqa-ok and openqa-failed labels."
    )

    parser.add_argument(
        '--compare-to-build',
        type=str,
        help="Provide build id to compare results to (looked up in the same version and 'update' flavor)."
    )

    parser.add_argument(
        '--instability',
        action='store_true',
        help="Report on test's instability."
    )

    parser.add_argument(
        '--verbose',
        action='store_true',
        help="Enable debug logging."
    )

    parser.add_argument(
        '--db-path',
        default=os.getenv("LOCAL_OPENQA_CACHE_PATH"),
        help="Local openQA cache for storing and query test results. "\
            "Can be set via the env variable LOCAL_OPENQA_CACHE_PATH. "\
            "Stored in memory only if not set. "
    )

    args = parser.parse_args()

    if (args.build or args.version or args.flavor) and args.job_id:
        parser.error(
            "Error: --latest required to use --build, --flavor and --version")
        return

    if not args.package_list:
        parser.error("Error: --package-list required.")
        return

    setup_environ(args)

    jobs = []

    if args.job_id:
        jobs.append(args.job_id)

    if args.latest:
        jobs = OpenQA.get_jobs_ids_for_build(args.build, args.version, args.flavor)
        if not jobs:
            parser.error('No jobs found for build id {}.'.format(args.build))
            return

    jobs = [OpenQA.get_job(job_id) for job_id in jobs]

    reference_jobs = None
    if args.compare_to_build:
        base_flavor = "update"
        if args.flavor in ("kernel",):
            base_flavor = args.flavor
        reference_jobs = OpenQA.get_jobs_ids_for_build(args.compare_to_build, args.version, base_flavor)
        if not reference_jobs:
            parser.error('No reference jobs found for build id {}.'.format(args.compare_to_build))
            return
        reference_jobs = [OpenQA.get_job(job_id) for job_id in reference_jobs]

    result = {}
    prs = set()
    for job in jobs:
        result.update(job.get_results())

        prs.update(job.get_related_github_objects())

    prs = sorted(prs)

    if args.instability:
        instability_analysis = InstabilityAnalysis(jobs)
    else:
        instability_analysis = None

    fill_results_context(result, jobs, reference_jobs, instability_analysis)

    formatted_result = format_results(result, jobs, reference_jobs,
                                      instability_analysis, github_links=prs)

    labels = get_labels_from_results(result)

    if args.show_results_only:
        print(formatted_result)
        print("Would label it with: {!r}".format(labels))
        return

    if args.show_github_issues_only:
        print(prs)
        return

    if not prs:
        print("Warning: no related pull requests and issues found.")
        return

    issue_title = ISSUE_TITLE_PREFIX + job.get_job_build()
    for pr in prs:
        issue = GitHubIssue(pr)
        issue.post_comment(formatted_result, title=issue_title)
        if args.enable_labels:
            issue.add_labels(labels)


if __name__ == '__main__':
    main()
