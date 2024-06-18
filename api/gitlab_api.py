#!/usr/bin/python3

# This service accepts requests to start openQA tests. It authenticates the
# request via a Gitlab CI JWT token which proves the request was made from
# particular job (it asks gitlab back to verify the token + return job
# details). Based on this info it decides whether given job can request a test
# run.

import subprocess
import sys
import os
import re
import json
import time
import requests
import tempfile
import string
import hmac
import hashlib
from flask import Flask, request, Response

GITLAB_API = 'https://gitlab.com/api/v4'

TARGET_REPO_DIR = '/var/lib/openqa/factory/repo'
TARGET_ISO_DIR = '/var/lib/openqa/factory/iso'


# defaults
config_defaults = {
    'owner_allowlist': 'QubesOS',
    'repo_allowlist': 'qubes-continuous-integration qubes-installer-qubes-os qubes-linux-kernel qubes-vmm-xen qubes-vmm-xen-stubdom-linux qubes-gui-agent-linux qubes-grub2',
    'repo_blocklist': None,
    'job_allowlist': '*',
    'user_allowlist': None,
    'branch_allowlist': 'master release4.0 release4.1 main',
    'github_webhook_key': None,
}

app = Flask(__name__)

def update_config():
    config = config_defaults.copy()
    for key, default in list(config.items()):
        config[key] = os.environ.get(key.upper(), default)

    return config

config = update_config()


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

def get_job_from_pr(pr_details):
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
            if job['status'] != 'success':
                continue
            if 'publish:repo' not in job['name']:
                continue
            return job['web_url']
    return None

@app.route('/api/run_test', methods=['POST'])
def run_test():

    resp = verify_if_job_allowed()
    if isinstance(resp, Response):
        return resp
    job_details = resp

    req_values = request.get_json()

    print(repr(req_values))

    version = req_values.get('VERSION') or '4.3'
    buildid = time.strftime('%Y%m%d%H-') + version
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
    values['VERSION'] = version
    values['FLAVOR'] = 'pull-requests'
    values['ARCH'] = 'x86_64'
    values['BUILD'] = buildid
    values['REPO_1'] = buildid
    values['KEY_1'] = repo_url + '/key.pub'
    values['UPDATE'] = '1'
    #values['GUIVM'] = '1'
    #values['UPDATE_TEMPLATES'] = 'fedora-34-xfce'
    values['PULL_REQUESTS'] = req_values['PULL_REQUESTS']
    if 'SELINUX_TEMPLATES' in req_values:
        values['SELINUX_TEMPLATES'] = req_values['SELINUX_TEMPLATES']
    if 'TEST_TEMPLATES' in req_values:
        values['TEST_TEMPLATES'] = req_values['TEST_TEMPLATES']
    if 'UPDATE_TEMPLATES' in req_values:
        values['UPDATE_TEMPLATES'] = req_values['UPDATE_TEMPLATES']
    if 'FLAVOR' in req_values and req_values['FLAVOR'] in ('pull-requests', 'kernel', 'whonix'):
        values['FLAVOR'] = req_values['FLAVOR']
    if 'KERNEL_VERSION' in req_values and req_values['KERNEL_VERSION'] in ('stable', 'latest'):
        values['KERNEL_VERSION'] = req_values['KERNEL_VERSION']

    subprocess.check_call([
        'openqa-cli', 'api', '-X', 'POST',
        'isos'] + ['='.join(p) for p in values.items()])

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

    return respond(200, 'nothing to do')

def run_test_pr(comment_details):
    comment_body = comment_details['body'].strip()
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

    # get associated gitlab job
    repo_job = get_job_from_pr(pr_details)
    if not repo_job:
        return respond(404, "build not found")

    version = comment_params.get("VERSION", "4.3")
    if not re.match(r"\A[0-9]\.[0-9]\Z", version):
        return respond(400, "invalid VERSION value")

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
    values['VERSION'] = version
    if pr_details['base']['repo']['name'] in (
            'qubes-linux-kernel',
            'qubes-gui-agent-linux',
            'qubes-grub2',
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
        .replace('/pulls/', '/pull/')

    subprocess.check_call([
        'openqa-cli', 'api', '-X', 'POST',
        'isos'] + ['='.join(p) for p in values.items()])

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
