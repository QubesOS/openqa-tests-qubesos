import sqlalchemy
from sqlalchemy import (
    Column, Boolean, Integer, String, Enum, PickleType,
    ForeignKey, create_engine
)
from sqlalchemy.orm import (
    sessionmaker, reconstructor, relationship, backref
)
import requests
import re
import json
import enum
import logging
import os
import sys

from lib.github_api import GitHubRepo, GitHubIssue, setup_github_environ
from lib.common import *

OPENQA_URL = "https://openqa.qubes-os.org"
OPENQA_API = OPENQA_URL + "/api/v1"

# repo for creating issues for FLAVOR=qubes-whonix jobs
WHONIX_NOTIFICATION_REPO = "Whonix/updates-status"

Base = sqlalchemy.orm.declarative_base()
local_session = None

name_mapping = {}

class PackageName:
    def __init__(self, line):
        self.package_name = None
        # component names to try
        self.component_names = []
        self.version = None
        self.release = None

        # meaningful Debian lines starts with 'ii'
        if line.startswith('ii '):
            columns = line.split()
            raw_name = columns[1]
            raw_version = columns[2]

            if raw_name in name_mapping:
                self.package_name = name_mapping[raw_name]

                if '-' in raw_version:
                    self.version = raw_version.split('-', maxsplit=1)[0]
                    self.release = raw_version.split('-', maxsplit=1)[1].split('+', maxsplit=1)[0]
                elif '+' in raw_version:
                    self.version = raw_version.split('+', maxsplit=1)[0]
                else:
                    self.version = raw_version

        # Fedora lines have no spaces
        if ' ' not in line:
            try:
                line_parts = line.split('-')
                package_name = "-".join(line_parts[:-2])
                if package_name in name_mapping:
                    self.version = line_parts[-2]
                    self.release = line_parts[-1].split('.', maxsplit=1)[0]
                    self.package_name = name_mapping[package_name]
            except IndexError:
                # the package name was malformed
                # and had an insufficient amount of '-'
                return
        if isinstance(self.package_name, list):
            self.component_names = self.package_name
            self.package_name = self.package_name[0]
        else:
            self.component_names = [self.package_name]

    def __eq__(self, other):
        return self.package_name == other.package_name \
               and self.version == other.version \
               and self.release == other.release

    def __lt__(self, other):
        if self.package_name == other.package_name:
            if self.version == other.version:
                return self.release < other.release
            return self.version < other.version
        return self.package_name < other.package_name

    def __str__(self):
        return "{} v{}-{}".format(self.package_name, self.version, self.release)

    def __hash__(self):
        return hash((self.package_name, self.version, self.release))


class JobData(Base):
    __tablename__ = 'job'

    job_id = Column(Integer, primary_key=True)
    job_name = Column(String)
    job_type = Column(String(50))
    job_details = Column(PickleType) # json
    valid = Column(Boolean)
    machine = Column(String)
    worker = Column(Integer)
    version = Column(Integer)
    flavor = Column(Integer)

    __mapper_args__ = {
        'polymorphic_identity':'job',
        'polymorphic_on': job_type
    }

    def __init__(self, job_id):
        self.job_id = job_id
        self.job_details = self.get_job_details()
        self.job_name = self.get_job_name()
        self.worker = self.get_job_worker()
        self.machine = self.get_job_machine()
        self.version = self.get_job_version()
        self.flavor = self.get_job_flavor()
        self.failures = {}

        # must flush at the beginning to avoid recursion
        logging.debug("Flushing {} {} to the database".format(
            self.job_type, self.job_id))
        local_session.add(self)
        local_session.flush()

        self.valid = self.is_valid()
        local_session.commit()

    def __hash__(self):
        return hash((self.job_id,))

    @property
    def clone_id(self):
        json_data = self.get_job_details()
        return json_data['job']['clone_id']

    @property
    def was_restarted(self):
        return self.clone_id != None

    @reconstructor
    def init_on_load(self):
        self.failures = {}

    @staticmethod
    def get_parent_job_id(job_id):
        job_details = requests.get(
            "{}/jobs/{}/details".format(OPENQA_API, job_id)).json()
        parents = job_details['job']['parents']['Chained']
        if len(parents) == 0:
            return None
        elif len(parents) == 1:
            return parents[0]
        if len(parents) > 1:
            raise Exception("Implementation does not support more than one "\
                            + "parent job.")

    def get_job_name(self):
        json_data = self.get_job_details()
        return json_data['job']['test']

    def get_job_combined_name(self):
        if self.machine == '64bit':
            return self.job_name
        else:
            return self.job_name + '@' + self.machine

    def get_job_build(self):
        json_data = self.get_job_details()
        return json_data['job']['settings']['BUILD']

    def get_job_flavor(self):
        json_data = self.get_job_details()
        return json_data['job']['settings']['FLAVOR']

    def get_job_version(self):
        """Qubes version of job"""
        json_data = self.get_job_details()
        return json_data['job']['settings']['VERSION']

    def get_job_start_time(self):
        json_data = self.get_job_details()
        return json_data['job']['t_started']

    def get_job_worker(self):
        json_data = self.get_job_details()
        try:
            return json_data['job']['assigned_worker_id']
        except KeyError:
            return -1

    def get_job_machine(self):
        """Machine "type": multiple machines can have the same one"""
        json_data = self.get_job_details()
        return json_data['job']['settings']['MACHINE']

    def get_job_details(self):
        if self.job_details is None:
            self.job_details = requests.get(self.get_job_api_url(details=True)).json()
        return self.job_details

    def is_valid(self):
        # TODO implement method
        return True

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
                                          self,
                                          test['num'])
                    if failure.is_valid():
                        if not TestFailure.exists_in_db(failure):
                            local_session.add(failure)
                            local_session.flush()
                        failure_list.append(failure)

        self.failures[self.get_job_combined_name()] = failure_list

        return self.failures

    def get_children_ids(self):
        json_data = self.get_job_details()
        return json_data['job']['children']['Chained']

    def get_children(self):
        return local_session.query(ChildJob)\
                            .filter(ChildJob.parent_job_id == self.job_id)\
                            .all()

    def get_children_pruned(self):
        """Gets children for the job but excludes restarted ones.

        In cases like job 24058 you have children that ran the same test. In
        that case the job 24060 and 24081 both ran the test suite with the name
        'system_tests_gui_tools' but the later is a clone the first one.
        With this method only the last one would be returned in the results.
        """

        results = {}

        for child in self.get_children():
            if not child.was_restarted:
                results[child.job_name] = child
        return results

    def get_children_results(self):
        result = {}

        children_list = self.get_children_pruned()
        for child in children_list.values():
            result[child.job_name] = child.get_results()[child.job_name]

        return result

    def get_dependency_url(self):
        url = "{}/tests/{}#dependencies".format(OPENQA_URL, self.job_id)
        return url

    def get_build_url(self):
        url = "{}/tests/overview?distri=qubesos&version={}&build={}&flavor={}".format(
            OPENQA_URL, self.get_job_version(), self.get_job_build(), self.get_job_flavor())
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
            if log == 'update-template-versions.txt' or log == 'update2-template-versions.txt':
                log_file = "{}/tests/{}/file/{}".format(
                    OPENQA_URL, self.job_id, log)

                template_list = requests.get(log_file).text.split('\n')
                for line in template_list:
                    all_templates.append(
                        re.sub(r"(.*)-([^-]*-[^-]*)(\.noarch)?", r"\1 \2", line))

        templates = []

        for template_name in test_templates:
            for package_name in all_templates:
                if package_name.startswith(
                        "qubes-template-{} ".format(template_name)):
                    templates.append(package_name)

        repo = GitHubRepo("updates-status")
        issue_urls = []

        for t in templates:
            issue_name = "{} (r{})".format(t, self.get_job_version())
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
            for name in p.component_names:
                issue_name = "{} v{}-{} (r{})".format(
                    name, p.version, p.release,
                    self.get_job_version())
                url = repo.get_issues_by_name(issue_name)
                if url is None:
                    issue_name = "{} v{} (r{})".format(
                        name, p.version,
                        self.get_job_version())
                    url = repo.get_issues_by_name(issue_name)
                if url:
                    issue_urls.append(url)
                    break

        return issue_urls

    def get_notification_issue(self, repo_name=None):
        json_data = self.get_job_details()

        issue_urls = []
        if json_data['job']['settings']['FLAVOR'] == 'qubes-whonix':
            issue_urls.append('{}/{}/issues/create-or-update'.format(
                              GITHUB_BASE_PREFIX, WHONIX_NOTIFICATION_REPO))

        return issue_urls

    def __str__(self):
        return self.job_name


class OrphanJob(JobData):
    """Jobs without parents"""

    __tablename__ = "orphan_job"
    __mapper_args__ = { 'polymorphic_identity':'orphan_job' }

    job_id = Column(ForeignKey('job.job_id'), primary_key=True)

    def __init__(self, job_id):
        super().__init__(job_id)

        # make sure children exist
        for child_id in self.get_children_ids():
            child = local_session.get(ChildJob, { "job_id": child_id })
            if child is None:
                child = ChildJob(child_id, parent_job=self)


class ChildJob(JobData):
    """Jobs with one parent"""

    __tablename__ = "child_job"
    __mapper_args__ = { 'polymorphic_identity':'child_job' }

    job_id = Column(Integer, ForeignKey('job.job_id'), primary_key=True)
    parent_job_id = Column(Integer, ForeignKey(OrphanJob.job_id))
    parent_job = relationship(
        OrphanJob, backref=backref("child_job", cascade="delete"),
        foreign_keys=[parent_job_id]
    )

    def __init__(self, job_id, parent_job_id=None, parent_job=None):
        super().__init__(job_id)

        if parent_job:
            self.parent_job = parent_job
        elif parent_job_id:
            parent_job = local_session.get(
                OrphanJob, { "job_id": parent_job_id })
            if parent_job is None:
                parent_job = OrphanJob(parent_job_id)
            self.parent_job = parent_job
        else:
            raise Exception("Must provide a parent_job_id or a parent_job")

    def is_valid(self):
        json_data = self.get_job_details()
        job_result = json_data['job']['result']
        if job_result == "passed":
            return True
        elif job_result == "failed":
            has_failures = len(self.get_results()[self.get_job_combined_name()]) > 0
            all_test_groups_ran = True

            for test_group in json_data['job']['testresults']:
                if test_group['result'] == 'none':
                    all_test_groups_ran = False

            # FIXME deal with edge-cases where 'system_tests' passes but no
            # external results are generated https://openqa.qubes-os.org/tests/20425

            return all_test_groups_ran and has_failures
        else:
            return False


class TestFailureReason(enum.Enum):
    SKIPPED = "skipped"
    ERROR = "error"
    FAILURE = "failure"
    UNKNOWN = "unknown"
    TEST_DIED = "test died"
    WAIT_SERIAL = "wait serial expected"

    @classmethod
    def get_invalid_reasons(cls):
        return [cls.UNKNOWN, cls.TEST_DIED, cls.WAIT_SERIAL]


class TestFailure(Base):
    __tablename__ = 'test_failures'

    name = Column(String, primary_key=True)
    title = Column(String, primary_key=True)
    job_id = Column(Integer, ForeignKey('job.job_id'), primary_key=True)
    job = relationship(
        JobData,
        backref=backref("test_failures", cascade="delete")
    )
    test_id = Column(Integer, primary_key=True)
    fail_reason = Column(Enum(TestFailureReason))
    relevant_error = Column(String)
    fail_error = Column(String)
    cleanup_error = Column(String)
    timed_out = Column(Boolean)
    has_description = Column(Boolean)
    template = Column(String(50))

    def __init__(self, name, title, description, job, test_id):
        self.name = name
        self.title = title
        self.job = job
        self.job_id = job.job_id
        self.test_id = test_id

        self.fail_reason = TestFailureReason.UNKNOWN
        self.relevant_error = None
        self.fail_error = None
        self.cleanup_error = None
        self.timed_out = False
        self.template = self.guess_template()

        if description is None:
            self.has_description = False
        else:
            self.has_description = True
            self.parse_description(description)

        # intentionally not stored in DB, makes sense only in a context
        self.unstable = False
        self.regression = False
        # a past failure that was fixed now
        self.fixed = False

    @staticmethod
    def exists_in_db(test_failure):
        return local_session.get(TestFailure,
                {"job_id": test_failure.job_id,
                 "name": test_failure.name,
                 "title": test_failure.title,
                 "test_id": test_failure.test_id})

    def get_test_url(self):
        return "{}/tests/{}#step/{}/{}".format(
            OPENQA_URL, self.job_id, self.name, self.test_id)

    def is_valid(self):
        if self.name != "system_tests":
            return True
        if self.fail_reason in TestFailureReason.get_invalid_reasons():
            return False
        if self.timed_out:
            return True
        return False

    def guess_template(self):
        # obtain template name according to construction format of
        # https://github.com/QubesOS/qubes-core-admin/blob/f60334/qubes/tests/__init__.py#L1352
        # Will catch most common tests.
        template = self.name.split("_")[-1]
        template = template.split("-pool")[0] # remove trailing "-pool"

        if re.search(r"^[a-z\-]+\-\d+(\-xfce)?$", template): # [template]-[ver]
            return template
        else:
            return "default"

    def parse_description(self, description):

        def get_relevant_error(max_chars=70):
            """Returns the error line(s) that best summarises the error (heuristic)

            The idea is to find the last traceback (when chained exceptions) and
            return the last line. An example bellow shows the relevant line as -->

            >    # test_003_cleanup_destroyed
            >    # error:
            >
            >    Traceback (most recent call last):
            >    File "/usr/lib/python3.8/site-packages/qubes/tests/integ/dispvm.py", line 94, in test_003_cleanup_destroyed
            >        self.loop.run_until_complete(asyncio.wait_for(p.wait(), timeout))
            >    File "/usr/lib64/python3.8/asyncio/base_events.py", line 616, in run_until_complete
            >        return future.result()
            >    File "/usr/lib64/python3.8/asyncio/tasks.py", line 501, in wait_for
            >        raise exceptions.TimeoutError()
            --> asyncio.exceptions.TimeoutError
            >
            >    # system-out:

            :param int max_chars: maximum number of characters in result
            """

            # find relevant line(s)
            try:
                i = len(lines) - 1
                while re.match("^\s", lines[i]): # non whitespace-starting
                    i -= 1
                while not re.match("^\s", lines[i]): # until it finds whitespace
                    i -= 1

                relev_line_prev = lines[i].strip()
                relev_line = lines[i+1].strip()

                # show relevant line (truncated if needed) and the previous one if
                # there is enough space.
                if len(relev_line) < max_chars - 30:
                    max_len_prev_line = max_chars -4 -len(relev_line)
                    return "{}... {}".format(
                        relev_line_prev[:max_len_prev_line],
                        relev_line)
                if len(relev_line) <= max_chars:
                    return relev_line
                else:
                    return relev_line[:max_chars-len("...")] + "..."
            except IndexError:
                raise Exception("Failed to extract error from: " + "\n".join(lines))


        max_chars=70
        if not self.has_description:
            return
        else:
            description = description.strip()

        if "timed out" in description:
            self.timed_out = True

        # non-standard error messages / test descriptions
        if "# system-out:" not in description:
            if "# wait_serial expected:" in description:
                self.fail_reason = TestFailureReason.WAIT_SERIAL
            if "# Test died: " in description:
                self.fail_reason = TestFailureReason.TEST_DIED

            first_line = description.split("\n")[0]
            self.relevant_error = first_line.strip()[:max_chars-3] + "..."
            self.fail_error = description
            return

        (self.fail_error, self.cleanup_error)=description.split("# system-out:")
        lines = self.fail_error.split("\n")

        # test case status https://github.com/os-autoinst/openQA/blob/dae9f4e5/lib/OpenQA/Parser/Format/JUnit.pm#L84
        if "# error:" in lines[1]:
            self.fail_reason = TestFailureReason.ERROR
        elif "# failure:" in lines[1]:
            self.fail_reason = TestFailureReason.FAILURE
        elif "# skipped:" in lines[1]:
            self.fail_reason = TestFailureReason.SKIPPED
            return
        else:
            self.fail_reason = TestFailureReason.UNKNOWN
            return
        self.relevant_error = get_relevant_error(max_chars=max_chars)

    def __str__(self):
        if not self.title:
            title = "unnamed test"
        else:
            title = self.title

        output = "{}: [{}]({})".format(self.name, title,
                                       self.get_test_url())

        if self.timed_out and self.cleanup_error:
            output += " ({} + timeout + cleanup)".format(self.fail_reason.value)
        elif self.timed_out:
            output += " ({} + timed out)".format(self.fail_reason.value)
        elif self.cleanup_error:
            output += " ({} + cleanup)".format(self.fail_reason.value)
        else:
            output += " ({})".format(self.fail_reason.value)

        if self.relevant_error and self.fail_reason!=TestFailureReason.SKIPPED:
            output += '\n `{}`\n'.format(self.relevant_error)

        return output

    def __eq__(self, other):
        if self.name == getattr(other, "name"):
            if not self.title:
                return self.test_id == getattr(other, "test_id")
            else:
                return self.title == getattr(other, "title")
        return False


class OpenQA:
    @staticmethod
    def get_job(job_id):
        logging.debug("getting job {} ".format(job_id))
        job = local_session.get(JobData, {"job_id": job_id})
        if job is None:
            parent_job_id = JobData.get_parent_job_id(job_id)
            if parent_job_id is None:
                logging.debug("creating orphan job for " + str(job_id))
                job = OrphanJob(job_id)
            else:
                logging.debug("creating child job for " + str(job_id))
                job = ChildJob(job_id, parent_job_id)
        return job

    def get_jobs(job_ids):
        jobs = []
        for job_id in job_ids:
            jobs += [OpenQA.get_job(job_id)]
        return jobs

    @staticmethod
    def get_latest_job_id(job_type='system_tests_update', build=None,
                          version=None, flavor=None, machine=None):
        jobs = OpenQA.get_latest_job_ids(job_type, build, version,
                                         history_len=1, flavor=flavor, machine=machine)
        if not jobs:
            return None
        return jobs[0]

    @staticmethod
    def get_latest_job_ids(job_type='system_tests_update', build=None,
                          version=None, history_len=100, result=None, flavor=None, machine=None):
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
        if machine:
            params.append('machine={}'.format(machine))

        if params:
            params_string = '?' + "&".join(params)
        else:
            params_string = ''

        data = requests.get(
            OPENQA_API + '/jobs' + params_string).json()

        jobs = []

        try:
            for job in data['jobs']:
                jobs.append(job['id'])
        except KeyError:
            # no jobs found
            pass
        return sorted(jobs)

    @staticmethod
    def get_jobs_ids_for_build(build, version, flavor):
        params = []
        params.append('build={}'.format(build))
        params.append('version={}'.format(version))
        params.append('flavor={}'.format(flavor))

        if params:
            params_string = '?' + "&".join(params)
        else:
            params_string = ''

        data = requests.get(
            OPENQA_API + '/jobs' + params_string).json()

        jobs = []

        try:
            for job in data['jobs']:
                # skip restarted job
                if job['clone_id']:
                    continue
                jobs.append(job['id'])
        except KeyError:
            # no jobs found
            pass
        return sorted(jobs)

    @staticmethod
    def get_latest_concluded_job_ids(test_suite, history_len, version, flavor, machine=None):
        success_jobs = OpenQA.get_latest_job_ids(test_suite, version=version,
                            result="passed",  history_len=history_len,
                            flavor=flavor, machine=machine)

        failed_jobs = OpenQA.get_latest_job_ids(test_suite, version=version,
                            result="failed",
                            history_len=history_len, flavor=flavor, machine=machine)

        job_ids = sorted(success_jobs + failed_jobs)
        job_ids = job_ids[-history_len:]
        return job_ids

    @staticmethod
    def get_n_jobs_like(reference_job, n, flavor_override=None):
        """Obtains similar n number of concluded valid jobs

        :param JobData reference_job: job whose params serve as a search base
        :param str n: number of similar jobs to obtain
        :param str flavor: overriding flavor
        """
        test_suite  = reference_job.get_job_name()
        if '@' in test_suite:
            test_suite, machine = test_suite.rsplit('@', 1)
        else:
            test_suite, machine = test_suite, '64bit'
        version     = reference_job.get_job_version()
        if flavor_override:
            flavor = flavor_override
        else:
            flavor = reference_job.get_job_flavor()

        latest_job_id = OpenQA.get_latest_job_id(
            job_type=test_suite, version=version, flavor=flavor, machine=machine)
        if latest_job_id is None:
            return []
        margin = n * 2 # add margin for invalid jobs
        max_history_len = max(latest_job_id - reference_job.job_id, 0) + margin

        job_ids = OpenQA.get_latest_concluded_job_ids(
                    test_suite, max_history_len, version, flavor, machine=machine)
        if not job_ids:
            return []

        if reference_job.job_id in job_ids:
            ref_job_index = job_ids.index(reference_job.job_id)
        else:
            # try to find job with closest id before the reference job
            # (indicating temporal closeness)
            ref_job_distances = map(
                lambda job_id: reference_job.job_id - job_id, job_ids)
            ref_job_distances = filter( # remove jobs after reference job
                lambda distance: distance > 0, ref_job_distances)
            closest_job_id = reference_job.job_id - min(ref_job_distances)
            ref_job_index = job_ids.index(closest_job_id)

        potential_job_ids = job_ids[:ref_job_index]

        relevant_jobs = []
        for job_id in reversed(potential_job_ids):
            job = OpenQA.get_job(job_id)

            if job.is_valid():
                relevant_jobs = [job] + relevant_jobs
            if len(relevant_jobs) >= n:
                break
        return relevant_jobs


def config_db_session(db_path=None, debug_db=False):
    if db_path is None:
        db_engine = create_engine("sqlite:///:memory:", echo=debug_db)
        Base.metadata.create_all(db_engine)
    else:
        db_engine = create_engine("sqlite:///" + db_path, echo=debug_db)

        if os.path.exists(db_path):
            logging.info("Connecting to local DB in '{}'".format(db_path))
        else:
            logging.info("Creating local DB in '{}'".format(db_path))
            Base.metadata.create_all(db_engine)

    Session = sessionmaker(bind=db_engine)
    session = Session()

    return session

def get_db_session():
    global local_session
    return local_session

def setup_openqa_environ(package_list, db_path=None, verbose=False):
    global name_mapping
    with open(package_list) as package_file:
        data = json.load(package_file)
    name_mapping = data

    global local_session
    local_session = config_db_session(db_path, debug_db=False)
    if verbose:
        setup_logging()

def setup_logging():
    logging.basicConfig(format='%(asctime)s %(name)s: %(message)s')
    logging.getLogger().setLevel(logging.DEBUG)
