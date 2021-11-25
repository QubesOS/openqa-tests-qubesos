import json

import requests
from argparse import ArgumentParser
import re

from lib.github_api import setup_github_environ, GitHubIssue
from lib.openqa_api import setup_openqa_environ, OpenQA
from lib.common import ISSUE_TITLE_PREFIX, COMMENT_TITLE

def setup_environ(args):
    setup_github_environ(args.auth_token)
    setup_openqa_environ(args.package_list)

def format_results(results, job, reference_job=None):
    output_string = "{}\n" \
                    "Complete test suite and dependencies: {}\n" \
                    "## Failed tests\n".format(COMMENT_TITLE,
                                                job.get_dependency_url())
    number_of_failures = 0

    for k in results:
        if results[k]:
            output_string += '* ' + str(k) + "\n"
            for fail in results[k]:
                output_string += '  * ' + str(fail) + '\n'
                number_of_failures += 1

    if results.get('system_tests_update', []):
        output_string += "\nInstalling updates failed, skipping rest of the report!\n"
        return output_string

    if not number_of_failures:
        output_string += "No failures!\n"

    if reference_job:
        output_string += "## New failures\n" \
                            "Compared to: {}\n".format(
                            reference_job.get_dependency_url())

        if reference_job.job_name == 'system_tests_update':
            reference_job_results = reference_job.get_children_results()
        else:
            reference_job_results = reference_job.get_results()

        for k in results:
            current_fails = results[k]
            old_fails = reference_job_results.get(k, [])

            if not current_fails:
                continue

            add_to_output = ""
            for fail in current_fails:
                if fail in old_fails:
                    continue
                add_to_output += '  * ' + str(fail) + '\n'

            if add_to_output:
                output_string += '* ' + str(k) + "\n"
                output_string += add_to_output

        output_string += "## Fixed failures\n" \
                            "Compared to: {}\n".format(
                            reference_job.get_dependency_url())

        for k in reference_job_results:
            current_fails = results.get(k, [])
            old_fails = reference_job_results.get(k, [])

            if not old_fails:
                continue

            add_to_output = ""
            for fail in old_fails:
                if fail in current_fails:
                    continue
                add_to_output += '  * ' + str(fail) + '\n'

            if add_to_output:
                output_string += '* ' + str(k) + "\n"
                output_string += add_to_output

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
        '--compare-to-job',
        help="Provide job id to compare results to."
    )

    args = parser.parse_args()

    if (args.build or args.version) and args.job_id:
        parser.error(
            "Error: --latest required to use --build and --version")
        return

    if not args.package_list:
        parser.error("Error: --package-list required.")
        return

    setup_environ(args)

    jobs = []

    if args.job_id:
        jobs.append(args.job_id)

    if args.latest:
        jobs = OpenQA.get_latest_job_id(args.job_name, args.build, args.version)

    reference_job = None
    if args.compare_to_job:
        reference_job = OpenQA.get_job(args.compare_to_job)

    for job_id in jobs:
        job = OpenQA.get_job(job_id)
        result = job.get_results()
        if job.job_name == 'system_tests_update':
            result.update(job.get_children_results())

        formatted_result = format_results(result, job, reference_job)

        if args.show_results_only:
            print(formatted_result)
            return

        prs = job.get_related_github_objects()

        if args.show_github_issues_only:
            print(prs)
            return

        labels = job.get_labels_from_results(result)

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
