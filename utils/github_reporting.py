import json

import requests
from argparse import ArgumentParser
import os
import re

OPENQA_URL = "https://openqa.qubes-os.org"
OPENQA_API = OPENQA_URL + "/api/v1"

GITHUB_API_PREFIX = "https://api.github.com/repos"
GITHUB_BASE_PREFIX = "https://github.com"

COMMENT_TITLE = "# OpenQA test summary"

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

        if description is None or "\n" in description:
            self.description = None
        else:
            self.description = description

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


class JobData:
    def __init__(self, job_id, job_name=None,
                 time_started=None):
        self.job_id = job_id

        if not job_name:
            job_name = self.get_job_name()

        self.job_name = job_name

        self.time_started = time_started
        self.failures = {}

    def check_restarted(self, new_id, new_time_started):
        if new_time_started > self.time_started:
            self.job_id = new_id
            self.time_started = new_time_started

    def get_job_name(self):
        json_data = requests.get(self.get_job_api_url(details=False)).json()
        return json_data['job']['test']

    def get_results(self):
        if self.failures:
            return self.failures

        json_data = requests.get(self.get_job_api_url(details=True)).json()

        failure_list = []

        for test_group in json_data['job']['testresults']:
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

    def get_children_pruned(self):
        data = requests.get(
            "{}/jobs/{}/".format(OPENQA_API, self.job_id)).json()

        results = {}

        for child in data['job']['children']['Chained']:
            child_data = requests.get(self.get_job_api_url(
                details=False, job_id=child)).json()
            child_name = child_data['job']['test']
            child_started = child_data['job']['t_started']
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
        prs = self.get_pull_requests()
        if not prs:
            return self.get_update_issues()
        return prs

    def get_pull_requests(self):
        json_data = requests.get(self.get_job_api_url(details=True)).json()

        if 'PULL_REQUESTS' not in json_data['job']['settings']:
            return []

        pr_raw_list = json_data['job']['settings']['PULL_REQUESTS']

        pr_list = pr_raw_list.strip().split(" ")

        return pr_list

    def get_update_issues(self):
        json_data = requests.get(self.get_job_api_url(details=True)).json()

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

    @staticmethod
    def get_labels_from_results(results):
        number_of_failures = sum(len(val) for val in results.values())
        if number_of_failures:
            return [LABEL_FAILED]
        return [LABEL_OK]

    def format_results(self, results):
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

        if not number_of_failures:
            output_string += "No failures!\n"

        return output_string

    def __str__(self):
        return self.job_name


class GitHubRepo:
    def __init__(self, repo_name, owner="QubesOS"):
        self.data = []
        self.repo = repo_name
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
        self.url, self.issue_no = self.parse_url(url)

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

    @staticmethod
    def parse_url(url):
        pattern = r'{}/(\w+)/([\w\-]+)/(issues|pull)/(\d+)#?.*'.format(
            GITHUB_BASE_PREFIX)
        match = re.compile(pattern).match(url)

        owner = match.group(1)
        repo = match.group(2)
        no = match.group(4)

        parsed_url = "{}/{}/{}/issues/".format(
                GITHUB_API_PREFIX,
                owner,
                repo,
                no)

        return parsed_url, no

    def post_comment(self, message_text):
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
        url = self.url + "{}/labels"
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
        params = []
        if job_type:
            params.append('test={}'.format(job_type))
        if build:
            params.append('build={}'.format(build))
        if version:
            params.append('version={}'.format(version))

        if params:
            params_string = '?' + "&".join(params)
        else:
            params_string = ''

        data = requests.get(
            OPENQA_API + '/jobs/overview' + params_string).json()

        results = []

        for job in data:
            results.append(job['id'])

        return results


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
        '--enable-labels',
        action='store_true',
        help="Enable adding openqa-ok and openqa-failed labels."
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

    for job_id in jobs:
        job = JobData(job_id)
        if job.job_name == 'system_tests_update':
            result = job.get_children_results()
        else:
            result = job.get_results()

        formatted_result = job.format_results(result)

        if args.show_results_only:
            print(formatted_result)
            return

        prs = job.get_related_github_objects()
        labels = job.get_labels_from_results(result)

        if not prs:
            print("Warning: no related pull requests and issues found.")
            return

        for pr in prs:
            issue = GitHubIssue(pr)
            issue.post_comment(formatted_result)
            if args.enable_labels:
                issue.add_labels(labels)


if __name__ == '__main__':
    main()
