import requests
from argparse import ArgumentParser
import os
import re

OPENQA_URL = "https://openqa.qubes-os.org"
OPENQA_API = OPENQA_URL + "/api/v1"

GITHUB_API_PREFIX = "https://api.github.com/repos"
GITHUB_BASE_PREFIX = "https://github.com"

COMMENT_TITLE = "# OpenQA test summary"

github_auth = {}


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
        json_data = requests.get(
            "{}/jobs/{}".format(OPENQA_API, self.job_id)).json()
        return json_data['job']['test']

    def get_results(self):
        if self.failures:
            return self.failures

        json_data = requests.get(
            "{}/jobs/{}/details".format(OPENQA_API, self.job_id)).json()

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
            child_data = requests.get(
                "{}/jobs/{}/".format(OPENQA_API, child)).json()
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
            result[child.job_name] = child.get_results()

        return result

    def get_dependency_url(self):
        url = "{}/tests/{}#dependencies".format(OPENQA_URL, self.job_id)
        return url

    def get_details_url(self):
        url = "{}/tests/{}#".format(OPENQA_URL, self.job_id)
        return url

    def get_pull_requests(self):
        json_data = requests.get(
            "{}/jobs/{}/details".format(OPENQA_API, self.job_id)).json()

        if 'PULL_REQUESTS' not in json_data['job']['settings']:
            return []

        pr_raw_list = json_data['job']['settings']['PULL_REQUESTS']

        pr_list = pr_raw_list.strip().split(" ")

        return pr_list

    def format_results(self, results):
        output_string = "{}\n" \
                        "Complete test suite: {}\n" \
                        "## Failed tests\n".format(COMMENT_TITLE,
                                                   self.get_dependency_url())

        for k in results:
            if results[k]:
                output_string += '* ' + str(k) + "\n"
                for fail in results[k]:
                    output_string += '  * ' + str(fail) + '\n'

        return output_string

    def __str__(self):
        return self.job_name


class GitHubIssue:
    def __init__(self, url):
        self.url, self.issue_no = self.parse_url(url)
        self.init_github_auth()

    @staticmethod
    def init_github_auth():
        if not github_auth:
            assert 'GITHUB_API_KEY' in os.environ
            github_auth['Authorization'] = \
                'token {}'.format(os.environ['GITHUB_API_KEY'])

    def existing_comment(self):
        comments_url = self.url + '{}/comments'.format(self.issue_no)
        comments_json = requests.get(comments_url, headers=github_auth).json()

        for comment in comments_json:
            comment_title = comment['body'][:len(COMMENT_TITLE)]
            if comment_title == COMMENT_TITLE:
                return comment['id']

        return None

    @staticmethod
    def parse_url(url):
        pattern = r'{}/(\w+)/([\w\-]+)/(issues|pull)/(\d+)#?.*'.format(
            GITHUB_BASE_PREFIX)
        match = re.compile(pattern).match(url)

        owner = match.group(1)
        repo = match.group(2)
        # issue_type = 'pulls' if match.group(3) == 'pull' else match.group(3)
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


def main():
    parser = ArgumentParser(
        description="Update GitHub issues with test reporting")

    parser.add_argument(
        "--auth-token",
        help="Github authentication token (OAuth2)")

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
        help="Requires --latest. Build to look for.")
    parser.add_argument(
        '--version',
        help="Requires --latest. Version to look for.")

    args = parser.parse_args()

    if args.auth_token:
        github_auth['Authorization'] = \
            'token {}'.format(args.auth_token)
    elif 'GITHUB_API_KEY' in os.environ:
        github_auth['Authorization'] = \
            'token {}'.format(os.environ['GITHUB_API_KEY'])

    if (args.job_name or args.build or args.version) and args.job_id:
        print(
            "Error: --latest required to use --job-name, --build and --version")
        return

    jobs = []

    if args.job_id:
        jobs.append(args.job_id)

    if args.latest:
        jobs = OpenQA.get_latest_job_id(args.job_name, args.build, args.version)

    for job_id in jobs:
        job = JobData(job_id)
        if job.job_name == 'system_tests_update':
            result = job.format_results(job.get_children_results())
        else:
            result = job.format_results(job.get_results())

        # here will be dragons
        prs = job.get_pull_requests()
        for pr in prs:
            issue = GitHubIssue(pr)
            issue.post_comment(result)


if __name__ == '__main__':
    main()
