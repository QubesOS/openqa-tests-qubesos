import sqlalchemy
from sqlalchemy import Column, Boolean, Integer, String, Enum, ForeignKey
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, scoped_session, reconstructor
from sqlalchemy.orm import relationship, backref
import requests
import requests_cache
import re
import json
import enum
import logging
import os

from lib.github_api import GitHubRepo, GitHubIssue, setup_github_environ
from lib.common import *

requests_cache.install_cache('openqa_cache', backend='sqlite', expire_after=8200)

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


class JobData(Base):
    __tablename__ = 'job'

    job_id = Column(Integer, primary_key=True)
    job_name = Column(String)
    job_type = Column(String(50))
    time_started = Column(String(20))

    __mapper_args__ = {
        'polymorphic_identity':'job',
        'polymorphic_on': job_type
    }

    def __init__(self, job_id, job_name=None, time_started=None):
        self.job_id = job_id

        if not job_name:
            job_name = self.get_job_name()
        self.job_name = job_name

        self.time_started = time_started
        self.job_details = None
        self.failures = {}

        local_session.add(self)
        local_session.commit()

    @reconstructor
    def init_on_load(self):
        self.job_details = None
        self.failures = {}

    @classmethod
    def get_parent_job_id(cls, job_id):
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
                                          self,
                                          test['num'])
                    if failure.is_valid():
                        if not TestFailure.exists_in_db(failure):
                            local_session.add(failure)
                            local_session.commit()
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

        for child_id in data['job']['children']['Chained']:
            child_data = requests.get(self.get_job_api_url(
                details=False, job_id=child_id)).json()
            child_name = child_data['job']['test']
            child_started = child_data['job']['t_started'] or '0'
            if child_name in results:
                results[child_name].check_restarted(child_id, child_started)
            else:
                child = local_session.get(ChildJob, {"job_id": child_id})
                if child is None:
                    child = ChildJob(child_id, job_name=child_name,
                                     parent_job_id=self.job_id,
                                     time_started=child_started)
                results[child_name] = child

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


class OrphanJob(JobData):
    """Jobs without parents"""

    __tablename__ = "orphan_job"
    __mapper_args__ = { 'polymorphic_identity':'orphan_job' }

    job_id = Column(ForeignKey('job.job_id'), primary_key=True)


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

    def __init__(self, job_id, parent_job_id, job_name=None, time_started=None):
        parent_job = local_session.get(OrphanJob, { "job_id": parent_job_id })
        if parent_job is None:
            parent_job = OrphanJob(parent_job_id)
        self.parent_job = parent_job

        super().__init__(job_id, job_name, time_started)


class TestFailureReason(enum.Enum):
    SKIPPED = "skipped"
    ERROR = "error"
    FAILURE = "failure"
    UNKNOWN = "unkown"
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

        if description is None:
            self.has_description = False
        else:
            self.has_description = True
            self.parse_description(description)

    @classmethod
    def exists_in_db(cls, test_failure):
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
        job = local_session.get(JobData, {"job_id": job_id})
        if job is None:
            parent_job_id = JobData.get_parent_job_id(job_id)
            if parent_job_id is None:
                logging.debug("creating orphan job for " + str(job_id))
                return OrphanJob(job_id)
            else:
                logging.debug("creating child job for " + str(job_id))
                return ChildJob(job_id, parent_job_id)
        return job

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

def get_db_session(in_memory=True, read_only=False, debug_db=True):

    def flush_block_writes(*args,**kwargs):
        logging.info("Writing to the DB is blocked: database in read-only mode")
        return

    if in_memory and read_only:
        raise Exception("A read-only in-memory database doesn't make sense")

    if in_memory:
        db_engine = create_engine("sqlite:///:memory:", echo=debug_db)
        Base.metadata.create_all(db_engine)

    elif not in_memory:
        db_file = "openqa_db.sqlite"
        db_engine = create_engine("sqlite:///" + db_file, echo=debug_db)

        if os.path.exists(db_file):
            logging.info("Connecting to local DB in '{}'".format(db_file))
        else:
            if read_only:
                raise Exception("Local DB does not exist in {}".format(db_file)
                                + "hence it cannot be set to read_only")

            logging.info("Creating local DB in '{}'".format(db_file))
            Base.metadata.create_all(db_engine)

    if read_only:
        Session = sessionmaker(bind=db_engine, autoflush=False,
                            autocommit=False)
        session = Session()
        session.flush = flush_block_writes
    else:
        Session = sessionmaker(bind=db_engine)
        session = Session()

    return session

def setup_openqa_environ(package_list, cache_results=True):
    global name_mapping
    with open(package_list) as package_file:
        data = json.load(package_file)

    name_mapping = data

    global local_session
    local_session = get_db_session(in_memory=not cache_results, debug_db=False)
