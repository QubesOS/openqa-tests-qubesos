import json

import requests
from argparse import ArgumentParser
import os
import re

OPENQA_URL = "https://openqa.qubes-os.org"
OPENQA_API = OPENQA_URL + "/api/v1"

GITHUB_API_PREFIX = "https://api.github.com/repos"
GITHUB_BASE_PREFIX = "https://github.com"

# repo for creating issues for FLAVOR=qubes-whonix jobs
WHONIX_NOTIFICATION_REPO = "Whonix/updates-status"

COMMENT_TITLE = "# OpenQA test summary"

ISSUE_TITLE_PREFIX = "OpenQA test result for build "

LABEL_OK = 'openqa-ok'
LABEL_FAILED = 'openqa-failed'

github_auth = {}

name_mapping = {}


class PackageName:
    def __init__(self, line):
        self.package_name = None
        self.version = None

        # meaningful Debian lines starts with 'ii'
        if line.startswith('ii '):
            columns = line.split()
            raw_name = columns[1]
            raw_version = columns[2]

            if raw_name in name_mapping:
                self.package_name = name_mapping[raw_name]

                if '-' in raw_version:
                    self.version = raw_version.split('-', maxsplit=1)[0]
                elif '+' in raw_version:
                    self.version = raw_version.split('+', maxsplit=1)[0]
                else:
                    self.version = raw_version
                return

        # Fedora lines have no spaces
        if ' ' not in line:
            try:
                line_parts = line.split('-')
                package_name = "-".join(line_parts[:-2])
                if package_name in name_mapping:
                    self.version = line_parts[-2]
                    self.package_name = name_mapping[package_name]
            except IndexError:
                # the package name was malformed
                # and had an insufficient amount of '-'
                return

    def __eq__(self, other):
        return self.package_name == other.package_name \
               and self.version == other.version

    def __lt__(self, other):
        if self.package_name == other.package_name:
            return self.version < other.version
        return self.package_name < other.package_name

    def __str__(self):
        return "{} v{}".format(self.package_name, self.version)

    def __hash__(self):
        return hash((self.package_name, self.version))


class TestFailure:
    def __init__(self, name, title, description, job_id, test_id):
        self.name = name
        self.title = title
        self.job_id = job_id
        self.test_id = test_id

        if description is None:
            self.description = None
            self.error_message = None
        elif "\n" in description.strip():
            self.description = None
            self.error_message = description.strip()
        else:
            self.description = description.strip()
            self.error_message = self.description

    def get_test_url(self):
        return "{}/tests/{}#step/{}/{}".format(
            OPENQA_URL, self.job_id, self.name, self.test_id)

    def is_valid(self):
        if self.name != "system_tests":
            return True
        if not self.description:
            return False
        if "timed out" in self.description:
            return True
        return False

    def __str__(self):
        if not self.title:
            title = "unnamed test"
        else:
            title = self.title

        output = "{}: [{}]({})".format(self.name, title,
                                       self.get_test_url())

        if self.description:
            output += ' (`{}`)'.format(self.description)

        return output

    def __eq__(self, other):
        if self.name == getattr(other, "name"):
            if not self.title:
                return self.test_id == getattr(other, "test_id")
            else:
                return self.title == getattr(other, "title")
        return False


class JobData:
    def __init__(self, job_id, job_name=None,
                 time_started=None):
        self.job_id = job_id

        if not job_name:
            job_name = self.get_job_name()

        self.job_name = job_name

        self.time_started = time_started
        self.failures = {}
        self.job_details = None

    def check_restarted(self, new_id, new_time_started):
        if new_time_started > self.time_started:
            self.job_id = new_id
            self.time_started = new_time_started

    def get_job_name(self):
        json_data = requests.get(self.get_job_api_url(details=False)).json()
        return json_data['job']['test']

    def get_job_build(self):
        json_data = self.get_job_details()
        return json_data['job']['settings']['BUILD']

    def get_job_flavor(self):
        json_data = self.get_job_details()
        return json_data['job']['settings']['FLAVOR']

    def get_job_start_time(self):
        json_data = self.get_job_details()
        return json_data['job']['t_started']

    def get_job_parent(self):
        json_data = self.get_job_details()
        parents = json_data['job']['parents']['Chained']
        if len(parents) == 0:
            raise Exception("Job {} has no parents.".format(self.job_id)\
                            + " This may happen in some older tests.")
        if len(parents) > 1:
            raise Exception("Implementation does not support more than one "\
                            + "parent job.")
        return parents[0]

    def get_job_details(self):
        if self.job_details is None:
            self.job_details = requests.get(self.get_job_api_url(details=True)).json()
        return self.job_details

    def get_results(self):
        if self.failures:
            return self.failures

        json_data = self.get_job_details()

        failure_list = []

        for test_group in json_data['job']['testresults']:
            if test_group['result'] == 'passed':
                continue
            for test in test_group['details']:
                if test['result'] == 'fail':
                    failure = TestFailure(test_group['name'],
                                          test['display_title'],
                                          test.get('text_data', None),
                                          self.job_id,
                                          test['num'])
                    if failure.is_valid():
                        failure_list.append(failure)

        self.failures[self.job_name] = failure_list

        return self.failures

    def is_valid(self):
        json_data = self.get_job_details()
        job_result = json_data['job']['result']
        if job_result == "passed":
            return True
        elif job_result == "failed":
            has_failures = len(self.get_results()[self.job_name]) > 0
            all_test_groups_ran = True

            for test_group in json_data['job']['testresults']:
                if test_group['result'] == 'none':
                    all_test_groups_ran = False

            # FIXME deal with edge-cases where 'system_tests' passes but no
            # external results are generated https://openqa.qubes-os.org/tests/20425

            return all_test_groups_ran and has_failures
        else:
            return False

    def get_children_pruned(self):
        data = requests.get(
            "{}/jobs/{}/".format(OPENQA_API, self.job_id)).json()

        results = {}

        for child in data['job']['children']['Chained']:
            child_data = requests.get(self.get_job_api_url(
                details=False, job_id=child)).json()
            child_name = child_data['job']['test']
            child_started = child_data['job']['t_started'] or '0'
            if child_name in results:
                results[child_name].check_restarted(child, child_started)
            else:
                results[child_name] = JobData(child, job_name=child_name,
                                              time_started=child_started)

        return results

    def get_children_results(self):
        children_list = self.get_children_pruned()

        result = {}

        for child in children_list.values():
            result[child.job_name] = child.get_results()[child.job_name]

        return result

    def get_dependency_url(self):
        url = "{}/tests/{}#dependencies".format(OPENQA_URL, self.job_id)
        return url

    def get_details_url(self):
        url = "{}/tests/{}#".format(OPENQA_URL, self.job_id)
        return url

    def get_job_api_url(self, details, job_id=None):
        if not job_id:
            job_id = self.job_id
        if details:
            return "{}/jobs/{}/details".format(OPENQA_API, job_id)
        else:
            return "{}/jobs/{}".format(OPENQA_API, job_id)

    def get_related_github_objects(self):
        notification_issues = self.get_notification_issue()
        if notification_issues:
            return notification_issues

        prs = self.get_pull_requests()
        if prs:
            return prs

        update_templates = self.get_template_issues()
        if update_templates:
            return update_templates

        return self.get_update_issues()

    def get_pull_requests(self):
        if self.job_details is None:
            self.job_details = requests.get(self.get_job_api_url(details=True)).json()
        json_data = self.job_details

        if 'PULL_REQUESTS' not in json_data['job']['settings']:
            return []

        pr_raw_list = json_data['job']['settings']['PULL_REQUESTS']

        pr_list = pr_raw_list.strip().split(" ")

        return pr_list

    def get_template_issues(self):
        json_data = self.get_job_details()

        test_templates = json_data['job']['settings'].get('TEST_TEMPLATES')
        if not test_templates:
            return []

        test_templates = test_templates.split(" ")

        all_templates = []

        for log in json_data['job']['ulogs']:
            if log == 'update-template-versions.txt':
                log_file = "{}/tests/{}/file/{}".format(
                    OPENQA_URL, self.job_id, log)

                template_list = requests.get(log_file).text.split('\n')
                for line in template_list:
                    all_templates.append(
                        re.sub(r"(.*)-([^-]*-[^-]*)\.noarch", r"\1 \2", line))

        templates = []

        for template_name in test_templates:
            for package_name in all_templates:
                if package_name.startswith(
                        "qubes-template-{} ".format(template_name)):
                    templates.append(package_name)

        repo = GitHubRepo("updates-status")
        issue_urls = []

        for t in templates:
            issue_name = "{} (r{})".format(
               t, json_data['job']['settings']['VERSION'])
            url = repo.get_issues_by_name(issue_name)
            if url:
                issue_urls.append(url)

        return issue_urls

    def get_update_issues(self):
        json_data = self.get_job_details()

        logs_to_check = []

        for log in json_data['job']['ulogs']:
            if log.endswith("packages.txt"):
                logs_to_check.append("{}/tests/{}/file/{}".format(
                    OPENQA_URL, self.job_id, log))

        packages = set()

        for log_url in logs_to_check:
            log = requests.get(log_url).text.split('\n')
            for line in log:
                package = PackageName(line)
                if package.package_name:
                    packages.add(package)

        # Validate if there are no copies of the same package with different
        # versions
        for package1 in packages:
            for package2 in packages:
                if package1.package_name == package2.package_name and \
                        package1.version != package2.version:
                    print(
                        "Warning: found package {} in two different versions: "
                        "{} and {}".format(
                            package1.package_name, package1.version,
                            package2.version))

        repo = GitHubRepo("updates-status")
        issue_urls = []

        for p in packages:
            issue_name = "{} v{} (r{})".format(
                p.package_name, p.version,
                json_data['job']['settings']['VERSION'])
            url = repo.get_issues_by_name(issue_name)
            if url:
                issue_urls.append(url)

        return issue_urls

    def get_notification_issue(self, repo_name=None):
        json_data = self.get_job_details()

        issue_urls = []
        if json_data['job']['settings']['FLAVOR'] == 'qubes-whonix':
            issue_urls.append('{}/{}/issues/create-or-update'.format(
                              GITHUB_BASE_PREFIX, WHONIX_NOTIFICATION_REPO))

        return issue_urls

    @staticmethod
    def get_labels_from_results(results):
        number_of_failures = sum(len(val) for val in results.values())
        if number_of_failures:
            return [LABEL_FAILED]
        return [LABEL_OK]

    def format_results(self, results, reference_job=None):
        output_string = "{}\n" \
                        "Complete test suite and dependencies: {}\n" \
                        "## Failed tests\n".format(COMMENT_TITLE,
                                                   self.get_dependency_url())
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

    def __str__(self):
        return self.job_name


class GitHubRepo:
    def __init__(self, repo_name, owner="QubesOS"):
        self.data = []
        self.owner = owner
        self.repo = repo_name
        self.repo_url = "{}/{}/{}".format(GITHUB_BASE_PREFIX, owner, self.repo)
        self.url = "{}/{}/{}/". format(GITHUB_API_PREFIX, owner, self.repo)

    def get_issues_by_name(self, name):

        for json_data in self.data:
            for issue in json_data:
                if issue['title'] == name:
                    return issue['html_url']

        url = self.url + 'issues'
        while url:
            data = requests.get(url, headers=github_auth)
            json_data = data.json()
            self.data.append(json_data)

            for issue in json_data:
                if issue['title'] == name:
                    return issue['html_url']

            if 'next' in data.links.keys():
                url = data.links['next']['url']
            else:
                url = None

class GitHubIssue:
    def __init__(self, url):
        self.existing_comment_no = None
        self.post_as_issue = False
        self.url, self.owner, self.repo, self.issue_no = self.parse_url(url)
        if self.issue_no == 'create-or-update':
            self.post_as_issue = True
            self.issue_no = None

    def existing_comment(self):
        if self.existing_comment_no:
            return self.existing_comment_no

        comments_url = self.url + '{}/comments'.format(self.issue_no)
        while comments_url:
            comments_data = requests.get(comments_url, headers=github_auth)
            comments_json = comments_data.json()

            for comment in comments_json:
                comment_title = comment['body'][:len(COMMENT_TITLE)]
                if comment_title == COMMENT_TITLE:
                    self.existing_comment_no = comment['id']
                    return self.existing_comment_no

            if 'next' in comments_data.links.keys():
                comments_url = comments_data.links['next']['url']
            else:
                comments_url = None

        return None

    def existing_issue(self, title):
        if self.issue_no is not None:
            return self.issue_no

        repo = GitHubRepo(self.repo, owner=self.owner)

        url = repo.get_issues_by_name(title)
        if url:
            self.issue_no = self.parse_url(url)[3]
            return self.issue_no

        return None

    @staticmethod
    def parse_url(url):
        pattern = r'{}/(\w+)/([\w\-]+)/(issues|pull)/(\d+|create-or-update)#?.*'.format(
            GITHUB_BASE_PREFIX)
        match = re.compile(pattern).match(url)

        owner = match.group(1)
        repo = match.group(2)
        no = match.group(4)

        parsed_url = "{}/{}/{}/issues/".format(
                GITHUB_API_PREFIX,
                owner,
                repo)

        return parsed_url, owner, repo, no

    def post_comment(self, message_text, title=None):
        if self.post_as_issue and not title:
            print('Posting as an issue requested, but no issue title given')
            return
        if self.post_as_issue:
            if self.existing_issue(title):
                api_method = requests.patch
                url = self.url + self.issue_no
            else:
                api_method = requests.post
                url = self.url[:-1]

            response = api_method(url,
                                  json={'title': title,
                                        'body': message_text},
                                  headers=github_auth)
        else:
            if self.existing_comment():
                url = self.url + 'comments/' + str(self.existing_comment())
                api_method = requests.patch
            else:
                url = self.url + '{}/comments'.format(self.issue_no)
                api_method = requests.post

            response = api_method(url,
                                  json={'body': message_text},
                                  headers=github_auth)

        if not response.ok:
            print("FAILED TO COMMENT. Error {}: {}".format(
                response.status_code, response.content))

    def add_labels(self, labels):
        # labels should be provided as a list of strings

        # check existing labels
        url = self.url + "{}/labels".format(self.issue_no)
        labels_to_remove = []

        if LABEL_OK in labels:
            labels_to_remove.append(LABEL_FAILED)
        if LABEL_FAILED in labels:
            labels_to_remove.append(LABEL_OK)

        result = requests.get(url, headers=github_auth).json()
        for label in result:
            if label['name'] in labels_to_remove:
                url_remove = url + "/" + label['name']
                requests.delete(url_remove, headers=github_auth)
            if label['name'] in labels:
                labels.remove(label['name'])

        if not labels:
            return

        url = self.url + "{}/labels".format(self.issue_no)
        result = \
            requests.post(url, json={'labels': labels}, headers=github_auth)

        if not result.ok:
            print("Warning: failed to add labels to issue.")


class OpenQA:
    @staticmethod
    def get_latest_job_id(job_type='system_tests_update', build=None,
                          version=None):
        return OpenQA.get_latest_job_ids(job_type, build, version, history_len=1)

    @staticmethod
    def get_latest_job_ids(job_type='system_tests_update', build=None,
                          version=None, history_len=100, result=None, flavor=None):
        params = []
        if job_type:
            params.append('test={}'.format(job_type))
        if build:
            params.append('build={}'.format(build))
        if version:
            params.append('version={}'.format(version))
        if history_len:
            params.append('limit={}'.format(history_len))
        if result:
            params.append('result={}'.format(result))
        if flavor:
            params.append('flavor={}'.format(flavor))

        if params:
            params_string = '?' + "&".join(params)
        else:
            params_string = ''

        data = requests.get(
            OPENQA_API + '/jobs' + params_string).json()

        jobs = []

        for job in data['jobs']:
            jobs.append(job['id'])

        return sorted(jobs)

def setup_environ(args):
    global name_mapping

    if args.auth_token:
        github_auth['Authorization'] = \
            'token {}'.format(args.auth_token)
    elif 'GITHUB_API_KEY' in os.environ:
        github_auth['Authorization'] = \
            'token {}'.format(os.environ['GITHUB_API_KEY'])

    with open(args.package_list) as package_file:
        data = json.load(package_file)

    name_mapping = data


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
        reference_job = JobData(args.compare_to_job)

    for job_id in jobs:
        job = JobData(job_id)
        result = job.get_results()
        if job.job_name == 'system_tests_update':
            result.update(job.get_children_results())

        formatted_result = job.format_results(result, reference_job)

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
