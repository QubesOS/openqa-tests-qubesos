#!/usr/bin/python3

# This service accepts requests to start openQA tests. It authenticates the
# request via a Gitlab CI JWT token which proves the request was made from
# particular job (it asks gitlab back to verify the token + return job
# details). Based on this info it decides whether given job can request a test
# run.

import dateutil
import subprocess
import sys
import os
import re
import json
import jwt
import time
import requests
import tempfile
import string
import hmac
import hashlib
from datetime import datetime, timezone
from flask import Flask, request, Response

GITLAB_API = 'https://gitlab.com/api/v4'
GITHUB_API = 'https://api.github.com'

TARGET_REPO_DIR = '/var/lib/openqa/factory/repo'
TARGET_ISO_DIR = '/var/lib/openqa/factory/iso'
STATE_DIR = '/var/lib/openqa/db'

ci_still_running = object()

# defaults
config_defaults = {
    'owner_allowlist': 'QubesOS',
    'repo_allowlist': 'qubes-continuous-integration qubes-installer-qubes-os qubes-linux-kernel qubes-vmm-xen qubes-vmm-xen-stubdom-linux qubes-gui-agent-linux qubes-grub2 qubes-app-linux-usb-proxy qubes-core-admin qubes-core-admin-linux qubes-core-libvirt',
    'repo_blocklist': None,
    'job_allowlist': '*',
    'user_allowlist': None,
    'branch_allowlist': 'master release4.0 release4.1 main',
    'github_webhook_key': None,
    'gitlab_trigger_token': None,
    'gitlab_trigger_url': 'https://gitlab.com/api/v4/projects/22463399/trigger/pipeline',
    'github_app_id': None,
    'github_app_key': None,
    'github_app_installation_id': None,
}

app = Flask(__name__)

class GithubAppCli:
    def __init__(self, app_id, private_key, installation_id):
        self.app_id = app_id
        self.private_key = private_key
        self.installation_id = installation_id

        self.token = None
        self.expires_at = 0

    def get_jwt(self):
        payload = {
            "iat": int(time.time()),
            "exp": int(time.time()) + (9 * 60),
            "iss": self.app_id,
        }
        bearer_token = jwt.encode(payload, self.private_key, algorithm="RS256")

        return bearer_token

    def gen_token(self):
        bearer_token = self.get_jwt()
        url = f"https://api.github.com/app/installations/{self.installation_id}/access_tokens"
        r = requests.post(
            url,
            headers={
                "Authorization": "Bearer {}".format(bearer_token),
                "Accept": "application/vnd.github.v3+json",
            },
        )
        r.raise_for_status()
        resp = r.json()
        self.token = resp["token"]
        expires = dateutil.parser.parse(resp["expires_at"])
        self.expires_at = datetime.combine(expires.date(),
                                           expires.time(),
                                           tzinfo=timezone.utc)
        log(f"Got new token, expires at {self.expires_at!r}")

    def get_token(self):
        if not self.token:
            self.gen_token()
        else:
            delta = self.expires_at - datetime.now(timezone.utc)
            if delta.total_seconds() <= 0:
                self.gen_token()

        return self.token

    def get_or_create_deployment(self, repo, ref):
        r = requests.get('/'.join([GITHUB_API, 'repos', repo, 'deployments']),
                          params={
                              'ref': ref,
                              'environment': 'qa',
                          },
                          headers={'Authorization': 'token {}'.format(self.get_token())},
                         )
        r.raise_for_status()
        deployments_list = r.json()
        if deployments_list:
            return deployments_list[0]['url']

        r = requests.post('/'.join([GITHUB_API, 'repos', repo, 'deployments']),
                          json={
                              'ref': ref,
                              'auto_merge': False,
                              'environment': 'qa',
                              'required_contexts': [],
                          },
                          headers={'Authorization': 'token {}'.format(self.get_token())},
                         )
        r.raise_for_status()
        return r.json()['url']

    def set_deployment_state(self, deployment_url, state, url=None, description=None):
        kwargs = {}
        if url:
            kwargs['log_url'] = url
        if description:
            kwargs['description'] = description
        r = requests.post('/'.join([deployment_url, 'statuses']),
                          json={
                              'state': state,
                              'environment': 'qa',
                              **kwargs,
                          },
                          headers={
                              'Authorization': 'token {}'.format(self.get_token()),
                              'Accept': 'application/vnd.github.ant-man-preview+json',
                          })
        log(f"deployment {deployment_url} set to {url}")
        r.raise_for_status()


def update_config():
    config = config_defaults.copy()
    for key, default in list(config.items()):
        config[key] = os.environ.get(key.upper(), default)

    return config

config = update_config()
github_app = None
if (config["github_app_installation_id"] and
        config["github_app_id"] and
        config["github_app_key"]):
    github_app = GithubAppCli(
        config["github_app_id"],
        config["github_app_key"],
        config["github_app_installation_id"])

def log(msg):
    print(str(msg), file=sys.stderr, flush=True)

def respond(status, msg=None):
    r = Response('OK' if status == 200 else 'ERROR', status=status, mimetype='text/plain')
    print(status, str(msg), file=sys.stderr, flush=True)
    if msg:
        r.set_data(msg)
    return r

def check_allowlist(item, allowlist):
    """ Checks if *item* is in space-separated *allowlist*.
    The check is case-insensitive. *allowlist* with a single `*` allows everything.
    """
    if allowlist == '*':
        return True
    if item.lower() in allowlist.lower().split():
        return True
    return False

def verify_if_job_allowed():
    """
    Check if job is allowed to use the API.

    Returns either job_details if allowed, or Reponse object if it isn't (to be
    returned to the client).
    """

    job_token = request.headers.get('JOB-TOKEN')
    if not job_token:
        return respond(403, 'Missing JOB-TOKEN header')

    # validate the token with gitlab, and retrieve job details

    r = requests.get(GITLAB_API + '/job', headers={'JOB-TOKEN': job_token})
    r.raise_for_status()

    job_details = r.json()

    print(repr(job_details))

    owner, repo = job_details['web_url'].lower().split('/')[3:5]

    if not check_allowlist(owner, config['owner_allowlist']):
        return respond(200, 'ignoring this owner')

    if not check_allowlist(repo, config['repo_allowlist']):
        return respond(200, 'ignoring this repo')

    if not check_allowlist(job_details['ref'], config['branch_allowlist']):
        return respond(200, 'ignoring this branch')

    if not check_allowlist(job_details['name'], config['job_allowlist']):
        return respond(200, 'ignoring this job')

    return job_details

def verify_webhook_obj():
    untrusted_data = request.data
    hmac_value = 'sha256=' + hmac.new(config['github_webhook_key'].encode(),
                                      untrusted_data,
                                      hashlib.sha256).hexdigest()
    if hmac_value != request.headers.get('X-Hub-Signature-256'):
        return respond(400, 'invalid hmac')

    webhook_obj = json.loads(untrusted_data)

    if 'repository' not in webhook_obj:
        return respond(200, 'ignoring non-repository hook')
    repo = webhook_obj['repository']['full_name']

    if config['owner_allowlist']:
        if repo.split('/')[0].lower() not in config['owner_allowlist'].lower().split():
            return respond(200, 'ignoring this owner')

    if config['repo_allowlist']:
        if repo.split('/')[1].lower() not in config['repo_allowlist'].lower().split():
            return respond(200, 'ignoring this repo')

    if config['repo_blocklist']:
        if repo.split('/')[1].lower() in config['repo_blocklist'].lower().split():
            return respond(200, 'ignoring this repo')

    return webhook_obj

def set_deployment_for_prs(prs, state, url=None, description=None):
    if not github_app:
        log("cannot set deployments without github app")
        return
    for pr in prs:
        pr_params = pr.replace('https://github.com/', '')
        repo, _, rest = pr_params.partition('/pull/')
        _, _, commit_id = rest.partition('/commits/')
        if not repo or not commit_id:
            print(f"Not setting deployment for {pr}, cannot parse url",
                  file=sys.stderr, flush=True)
            continue
        deployment = github_app.get_or_create_deployment(repo, commit_id)
        github_app.set_deployment_state(deployment, state, url, description)


def get_job_from_pr(pr_details, job_name="publish:repo"):
    """Search for publish job for a given PR

    Returns:
    - URL to the job, if found and completed
    - None if not found
    - False if found but still running
    """
    found_running = False

    r = requests.get(pr_details['_links']['statuses']['href'])
    r.raise_for_status()
    for status in r.json():
        if status['context'] != "continuous-integration/pullrequest":
            continue
        repo, _, pipeline = status['target_url'] \
                     .replace('https://gitlab.com/', '') \
                     .partition('/-/pipelines/')
        r = requests.get(f"{GITLAB_API}/projects/{repo.replace('/', '%2F')}/pipelines/{pipeline}/jobs")
        r.raise_for_status()
        for job in r.json():
            if job_name not in job['name']:
                continue
            if job['status'] in ['scheduled', 'running', 'preparing', 'pending', 'created']:
                found_running = True
            if job['status'] != 'success':
                continue
            return job['web_url']
    if found_running:
        return False
    return None

@app.route('/api/run_test', methods=['POST'])
def run_test():

    resp = verify_if_job_allowed()
    if isinstance(resp, Response):
        return resp
    job_details = resp

    req_values = request.get_json()

    print(repr(req_values))

    version = req_values.get('VERSION') or 'devel'
    buildid = time.strftime('%Y%m%d%H-') + version

    if 'TEST_TEMPLATES' in req_values:
        # append distro name to buildid if test is limited to some
        test_templates = req_values['TEST_TEMPLATES']
        distros = {val.split("-")[0] for val in test_templates.split()}
        if len(distros) == 1:
            buildid += "-" + distros.pop()

    # cannot serve repo directly from gitlab, because it refuses connections via Tor :/
    repo_url = req_values['REPO_JOB'] + '/artifacts/raw/repo'
    with requests.get(req_values['REPO_JOB'] + '/artifacts/download', stream=True) as r:
        r.raise_for_status()
        with tempfile.NamedTemporaryFile() as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
            f.flush()
            repo_dir = TARGET_REPO_DIR + '/' + buildid
            os.mkdir(repo_dir)
            subprocess.check_output(
                ['unzip', '-q', f.name, '-d', repo_dir])
            # get rid of 'repo' dir nesting
            for subdir in os.listdir(repo_dir + '/repo'):
                os.rename(repo_dir + '/repo/' + subdir, repo_dir + '/' + subdir)

    values = {}
    values['DISTRI'] = 'qubesos'
    if version == 'devel':
        values['VERSION'] = '4.3'
        values['REPO_DEVEL'] = '1'
    else:
        values['VERSION'] = version
    values['FLAVOR'] = 'pull-requests'
    values['ARCH'] = 'x86_64'
    values['BUILD'] = buildid
    values['REPO_1'] = buildid
    values['KEY_1'] = repo_url + '/key.pub'
    values['UPDATE'] = '1'
    #values['GUIVM'] = '1'
    #values['UPDATE_TEMPLATES'] = 'fedora-34-xfce'
    values['PULL_REQUESTS'] = " ".join(
        sorted(req_values['PULL_REQUESTS'].split(" "))
    )
    machines_list = [""]
    if 'SELINUX_TEMPLATES' in req_values:
        values['SELINUX_TEMPLATES'] = req_values['SELINUX_TEMPLATES']
    if 'TEST_TEMPLATES' in req_values:
        values['TEST_TEMPLATES'] = req_values['TEST_TEMPLATES']
    if 'UPDATE_TEMPLATES' in req_values:
        values['UPDATE_TEMPLATES'] = req_values['UPDATE_TEMPLATES']
    if 'DEFAULT_TEMPLATE' in req_values:
        values['DEFAULT_TEMPLATE'] = req_values['DEFAULT_TEMPLATE']
    if 'FLAVOR' in req_values and req_values['FLAVOR'] in ('pull-requests', 'kernel', 'whonix', 'templates'):
        values['FLAVOR'] = req_values['FLAVOR']
    if 'KERNEL_VERSION' in req_values and req_values['KERNEL_VERSION'] in ('stable', 'latest'):
        values['KERNEL_VERSION'] = req_values['KERNEL_VERSION']
    if 'QUBES_TEST_MGMT_TPL' in req_values:
        values['QUBES_TEST_MGMT_TPL'] = req_values['QUBES_TEST_MGMT_TPL'];
    if 'WHONIX_REPO' in req_values:
        values['WHONIX_REPO'] = req_values['WHONIX_REPO'];
    if 'DISTUPGRADE_TEMPLATES' in req_values:
        values['DISTUPGRADE_TEMPLATES'] = req_values['DISTUPGRADE_TEMPLATES']
    if 'TEST' in req_values:
        values['TEST'] = req_values['TEST']
    if 'MACHINE' in req_values:
        machines_list = req_values['MACHINE'].split(",")

    for machine in machines_list:
        subprocess.check_call([
            'openqa-cli', 'api', '-X', 'POST', 'isos']
            + ['='.join(p) for p in values.items()]
            + ([f"MACHINE={machine}"] if machine else [])
        )
    # https://openqa.qubes-os.org/tests/overview?distri=qubesos&version=4.3&build=2026050409-devel&groupid=11
    set_deployment_for_prs(req_values['PULL_REQUESTS'].split(" "),
        'success',
        f'https://openqa.qubes-os.org/tests/overview?distri=qubesos&version={values['VERSION']}&build={values['BUILD']}',
        'openQA run started')

    return respond(200, 'done')

@app.route('/api/github-event', methods=['POST'])
def github_event():
    resp = verify_webhook_obj()
    if isinstance(resp, Response):
        return resp
    webhook_obj = resp

    # issue/pr comment
    if 'comment' in webhook_obj and webhook_obj['action'] == 'created':
        if config['user_allowlist']:
            user = webhook_obj['comment']['user']['login']
            if user.lower() not in config['user_allowlist'].lower().split():
                return respond(200, 'comment of this user ignored')
        if webhook_obj['comment']['body'].lower().startswith('openqarun'):
            return run_test_pr(webhook_obj['comment'])
    if request.headers.get('X-GitHub-Event') == 'status':
        if webhook_obj['context'] != 'continuous-integration/pullrequest':
            return respond(200, "nothing to do for this status")
        commit_id = webhook_obj['sha']
        state_file = os.path.join(STATE_DIR, f"api-command-{commit_id}")
        if not os.path.exists(state_file):
            return respond(200, "no queued command")
        with open(state_file) as f:
            stored_command = json.load(f)
        # just to be sure
        if stored_command['repo'] != webhook_obj['repository']['full_name']:
            return respond(403, "repository mismatch")
        os.unlink(state_file)
        return run_test_pr(stored_command['comment'])

    return respond(200, 'nothing to do')


def schedule_pr_build(params, pr_details=None):
    if not config['gitlab_trigger_url'] or not config['gitlab_trigger_token']:
        return respond(404, "missing gitlab trigger config")

    allowlist_params = (
        "SELINUX_TEMPLATES",
        "UPDATE_TEMPLATES",
        "TEST_TEMPLATES",
        "DEFAULT_TEMPLATE",
        "TEST",
        "MACHINE",
        "FLAVOR",
        "KERNEL_VERSION",
        "DISTUPGRADE_TEMPLATES",
        "QUBES_TEST_MGMT_TPL",
        "WHONIX_REPO",
        "PR_LABEL",
    )
    # basic value validation done by the caller already
    req_params = {}
    for param in allowlist_params:
        if param in params:
            req_params[f"variables[{param}]"] = params[param]
    req_params["token"] = config['gitlab_trigger_token']
    req_params["ref"] = "main"
    r = requests.post(config['gitlab_trigger_url'],
        data=req_params)
    r.raise_for_status()
    if pr_details and github_app:
        # TODO: ideally it should set it on all selected PRs, but they get
        # enumerated only on the gitlab side, and enumerating them here
        # leads to TOCTOU issue
        deployment = github_app.get_or_create_deployment(
            pr_details['base']['repo']['full_name'],
            pr_details['head']['sha']
        )

        github_app.set_deployment_state(
            deployment,
            'in_progress',
            r.json()['web_url'],
            'openQA build scheduled'
        )

    return respond(200, "done")


def run_test_pr(comment_details):
    comment_body = comment_details['body'].strip()
    # basic validation, to avoid command injection
    if not re.match(r"[a-zA-Z0-9_,= -]*", comment_body):
        return respond(400, "invalid parameters format")

    comment_params = dict([
        param.split("=", 1)
        for param in comment_body.split(" ")
        if "=" in param and param[0].isupper()
    ])

    # get PR info
    issue_url = comment_details['issue_url']
    r = requests.get(issue_url)
    r.raise_for_status()
    pr_url = r.json()['pull_request']['url']
    r = requests.get(pr_url)
    r.raise_for_status()
    pr_details = r.json()
    commit_id = pr_details['head']['sha']

    if 'PR_LABEL' in comment_params:
        if not re.match(r"\A[a-z0-9-]+\Z", comment_params['PR_LABEL']):
            return respond(400, "invalid LABEL value")
        return schedule_pr_build(comment_params, pr_details)

    version = comment_params.get("VERSION", "devel")
    if version != 'devel' and not re.match(r"\A[0-9]\.[0-9]\Z", version):
        return respond(400, "invalid VERSION value")
    tests_list = comment_params.get("TEST", "")
    if tests_list and not re.match(r"\A([a-z0-9_]+,)*[a-z0-9_]+\Z", tests_list):
        return respond(400, "invalid TEST value")
    machine_list = comment_params.get("MACHINE", "")
    if machine_list and not re.match(r"\A([a-z0-9]+,)*[a-z0-9]+\Z", machine_list):
        return respond(400, "invalid MACHINE value")

    # get associated gitlab job
    job_versions = [f"r{version}"]
    if version == "devel":
        job_versions = ["devel", "r4.3"]
    for job_version in job_versions:
        repo_job = get_job_from_pr(pr_details, job_name=f"{job_version}:publish:repo")
        if repo_job:
            break
    if repo_job is False:
        state_file = os.path.join(STATE_DIR, f"api-command-{commit_id}")
        with open(state_file, "w") as f:
            json.dump({
                'repo': pr_details['base']['repo']['full_name'],
                'comment': comment_details
            },
            f)
        if github_app:
            deployment = github_app.get_or_create_deployment(
                pr_details['base']['repo']['full_name'],
                commit_id
            )

            github_app.set_deployment_state(
                deployment,
                'queued',
                None,
                'waiting for build to complete'
            )
        return respond(200, "queued")
    if not repo_job:
        return respond(404, "build not found")

    buildid = time.strftime('%Y%m%d%H%M-') + version
    # cannot serve repo directly from gitlab, because it refuses connections via Tor :/
    repo_url = repo_job + '/artifacts/raw/repo'
    with requests.get(repo_job + '/artifacts/download', stream=True) as r:
        r.raise_for_status()
        with tempfile.NamedTemporaryFile() as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
            f.flush()
            repo_dir = TARGET_REPO_DIR + '/' + buildid
            os.mkdir(repo_dir)
            subprocess.check_output(
                ['unzip', '-q', f.name, '-d', repo_dir])
            # get rid of 'repo' dir nesting
            for subdir in os.listdir(repo_dir + '/repo'):
                os.rename(repo_dir + '/repo/' + subdir, repo_dir + '/' + subdir)

    values = {}
    values['DISTRI'] = 'qubesos'
    if version == 'devel':
        values['VERSION'] = '4.3'
        values['REPO_DEVEL'] = '1'
    else:
        values['VERSION'] = version
    if pr_details['base']['repo']['name'] in (
            'qubes-linux-kernel',
            'qubes-gui-agent-linux',
            'qubes-grub2',
            'qubes-core-libvirt',
            'qubes-vmm-xen',
            'qubes-vmm-xen-stubdom-linux'):
        values['FLAVOR'] = 'kernel'
        if pr_details['base']['ref'] in ('master', 'main'):
            values['KERNEL_VERSION'] = 'latest'
        else:
            values['KERNEL_VERSION'] = 'stable'
    else:
        values['FLAVOR'] = 'pull-requests'
    values['ARCH'] = 'x86_64'
    values['BUILD'] = buildid
    values['REPO_1'] = buildid
    values['KEY_1'] = repo_url + '/key.pub'
    values['UPDATE'] = '1'
    #values['GUIVM'] = '1'
    #values['UPDATE_TEMPLATES'] = 'fedora-34-xfce'
    values['PULL_REQUESTS'] = pr_url\
        .replace('https://api.github.com/repos/', 'https://github.com/')\
        .replace('/pulls/', '/pull/') \
        + '/commits/' + commit_id
    if tests_list:
        values['TEST'] = tests_list

    for machine in set(machine_list.split(",")):
        subprocess.check_call([
            'openqa-cli', 'api', '-X', 'POST', 'isos']
            + ['='.join(p) for p in values.items()]
            + ([f"MACHINE={machine}"] if machine else [])
        )

    set_deployment_for_prs(
        values['PULL_REQUESTS'].split(" "),
        'success',
        f'https://openqa.qubes-os.org/tests/overview?distri=qubesos&version={values['VERSION']}&build={values['BUILD']}',
        'openQA run started')

    return respond(200, 'done')

@app.route('/api/run_test_iso', methods=['POST'])
def run_test_iso():

    resp = verify_if_job_allowed()
    if isinstance(resp, Response):
        return resp
    job_details = resp

    version = request.args.get('VERSION')
    if not all(x in string.digits+'.' for x in version):
        return respond(400, 'invalid RELEASE')

    buildid = time.strftime('%Y%m%d%H-' + version)
    iso_name = 'Qubes-' + buildid + '.iso'
    iso_path = os.path.join(TARGET_ISO_DIR, iso_name)
    if os.path.exists(iso_path):
        return respond(403, 'already exists')

    # cannot serve via gitlab artifacts because of 1GB size limit
    try:
        with open(iso_path, 'wb') as iso_file:
            chunk_size = 1024 * 1024  # 1MB
            while True:
                chunk = request.stream.read(chunk_size)
                if not chunk:
                    break
                iso_file.write(chunk)
    except:
        os.unlink(iso_path)
        raise

    values = {}
    values['DISTRI'] = 'qubesos'
    values['VERSION'] = version
    values['FLAVOR'] = 'install-iso'
    values['ARCH'] = 'x86_64'
    values['BUILD'] = buildid
    values['ISO'] = iso_name
    if version == '4.0':
        values['UEFI_DIRECT'] = '1'
    values['KERNEL_VERSION'] = request.args.get('KERNEL_VERSION', 'stable')

    subprocess.check_call([
        'openqa-cli', 'api', '-X', 'POST',
        'isos'] + ['='.join(p) for p in values.items()])

    return respond(200, 'done')


if __name__ == '__main__':
    #main()
    app.run(debug=True)
