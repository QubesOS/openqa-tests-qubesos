import requests
import os
import re

from lib.common import *

GITHUB_API_PREFIX = "https://api.github.com/repos"

github_auth = {}

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
        # if cache exists and issue wasn't found, don't fetch data again
        if self.data:
            return None

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

def get_labels_from_results(results):
    number_of_failures = sum(len(val) for val in results.values())
    if number_of_failures:
        return [LABEL_FAILED]
    return [LABEL_OK]

def setup_github_environ(auth_token):
    global github_auth

    if auth_token:
        github_auth['Authorization'] = \
            'token {}'.format(auth_token)
    elif 'GITHUB_API_KEY' in os.environ:
        github_auth['Authorization'] = \
            'token {}'.format(os.environ['GITHUB_API_KEY'])
