import requests
from argparse import ArgumentParser
import os
import subprocess
import sys
import re

OPENQA_URL = "https://openqa.qubes-os.org"
OPENQA_API = OPENQA_URL + "/api/v1"

GITHUB_API_PREFIX = "https://api.github.com/repos"
GITHUB_BASE_PREFIX = "https://github.com"

# GITHUB_ISSUES_REPO = "QubesOS/qubes-issues"
# GITHUB_UPDATES_REPO = "QubesOS/updates-status"
# GITHUB_REPO_PREFIX = "QubesOS/qubes-"
# GITHUB_BASEURL = "https://github.com/"


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
    def __init__(self, job_name, job_id, time_started):
        self.job_name = job_name
        self.job_id = job_id
        self.time_started = time_started
        self.failures = []

    def check_restarted(self, new_id, new_time_started):
        if new_time_started > self.time_started:
            self.job_id = new_id
            self.time_started = new_time_started

    def get_results(self):
        if self.failures:
            return self.failures

        json_data = requests.get(
            "{}/jobs/{}/details".format(OPENQA_API, self.job_id)).json()

        for test_group in json_data['job']['testresults']:
            for test in test_group['details']:
                if test['result'] == 'fail':
                    failure = TestFailure(test_group['name'],
                                          test['display_title'],
                                          test.get('text_data', None),
                                          self.job_id,
                                          test['num'])
                    if failure.is_valid():
                        self.failures.append(failure)

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
                results[child_name] = JobData(child_name, child, child_started)

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

    def format_results(self, results):
        output_string = "# OpenQA test summary\n" \
                        "Complete test suite: {}\n" \
                        "## Failed tests\n".format(self.get_dependency_url())

        for k in results:
            if results[k]:
                output_string += '* ' + str(k) + "\n"
                for fail in results[k]:
                    output_string += '  * ' + str(fail) + '\n'

        return output_string

    # dodac linka do calosci
    # albo do poszczegolnych testow i calosci

    def __str__(self):
        return self.job_name


class GitHubIssue:
    def __init__(self, url):
        self.owner, self.repo, self.type, self.no = self.parse_url(url)
        self.init_github_auth()

    @staticmethod
    def init_github_auth():
        if not github_auth:
            assert 'GITHUB_API_KEY' in os.environ
            github_auth['Authorization'] = \
                'token {}'.format(os.environ['GITHUB_API_KEY'])

    def existing_comment(self):
        # todo : check if a comment exists, return its ??? if it does or none is not
        return None

    @staticmethod
    def parse_url(url):
        pattern = r'{}/(\w+)/([\w\-]+)/(issues|pull)/(\d+)#?.*'.format(
            GITHUB_BASE_PREFIX)
        match = re.compile(pattern).match(url)

        owner = match.group(1)
        repo = match.group(2)
        issue_type = 'pulls' if match.group(3) == 'pull' else match.group(3)
        no = match.group(4)

        return owner, repo, issue_type, no

    def post_comment(self, message_text):

        # check if comment exists if yes change it if not edit it

        url = "{}/{}/{}/issues/{}/comments".format(
            GITHUB_API_PREFIX,
            self.owner,
            self.repo,
            self.no)

        print(url)

        response = requests.post(url,
            json={'body': message_text},
            headers=github_auth)

        if not response.ok:
            print("FAILED TO COMMENT. Error {}: {}".format(
                response.status_code, response.content))


def get_latest_update_job_id():
    data = requests.get(
        OPENQA_API + '/jobs/overview?test=system_tests_update').json()

    return data[0]['id']


def main():

    main_job_id = 3849

    main_job = JobData("system_tests_update", main_job_id, None)

    result = main_job.format_results(main_job.get_children_results())



    issue = GitHubIssue("https://github.com/marmarta/qubes-desktop-linux-manager/pull/1")
    print(github_auth)

    issue.post_comment(result)

# main_job_id = get_latest_update_job_id()
# print(get_latest_update_job_id())

def test1():
    main_job_id = 3849

    main_job = JobData("system_tests_update", main_job_id, None)

    result = main_job.get_children_results()

    for k in result:
        if result[k]:
            print(k)
            for fail in result[k]:
                print('   ' + str(fail))


# make it so that this automagically adds github comments


# so trzeba znalezc joby z settings - flavor - update
# i ich dzieci przelistowac

if __name__ == '__main__':
        main()