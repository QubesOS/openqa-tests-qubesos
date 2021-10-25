#!/usr/bin/python3

# This service accepts requests to start openQA tests. It authenticates the
# request via a Gitlab CI JWT token which proves the request was made from
# particular job (it asks gitlab back to verify the token + return job
# details). Based on this info it decides whether given job can request a test
# run.

import subprocess
import sys
import os
import json
import time
import requests
import zipfile
import tempfile
from flask import Flask, request, Response

GITLAB_API = 'https://gitlab.com/api/v4'

TARGET_REPO_DIR = '/var/lib/openqa/factory/repo'


# defaults
config_defaults = {
    'owner_allowlist': 'QubesOS',
    'repo_allowlist': 'qubes-continuous-integration',
    'job_allowlist': '*',
    'branch_allowlist': 'master',
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

@app.route('/api/run_test', methods=['POST'])
def run_test():

    resp = verify_if_job_allowed()
    if isinstance(resp, Response):
        return resp
    job_details = resp

    req_values = request.get_json()

    buildid = time.strftime('%Y%m%d%H-4.1')
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
            with zipfile.ZipFile(f.name, 'r') as repo_zip:
                repo_zip.extractall(repo_dir)
            # get rid of 'repo' dir nesting
            for subdir in os.listdir(repo_dir + '/repo'):
                os.rename(repo_dir + '/repo/' + subdir, repo_dir + '/' + subdir)

    values = {}
    values['DISTRI'] = 'qubesos'
    values['VERSION'] = '4.1'
    values['FLAVOR'] = 'pull-requests'
    values['ARCH'] = 'x86_64'
    values['BUILD'] = buildid
    values['REPO_1'] = buildid
    values['KEY_1'] = repo_url + '/key.pub'
    values['UPDATE'] = '1'
    values['GUIVM'] = '1'
    values['UPDATE_TEMPLATES'] = 'fedora-34-xfce'
    values['PULL_REQUESTS'] = req_values['PULL_REQUESTS']

    subprocess.check_call([
        'openqa-cli', 'api', '-X', 'POST',
        'isos'] + ['='.join(p) for p in values.items()])

    return respond(200, 'done')


if __name__ == '__main__':
    #main()
    app.run(debug=True)
