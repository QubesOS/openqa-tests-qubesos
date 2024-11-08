#!/usr/bin/python3

import os.path
import pika
import json
import argparse
import collections
import requests
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
DEFAULT_PACKAGE_LIST = os.path.join(SCRIPT_DIR, 'github_package_mapping.json')
DEFAULT_JOBS_COMPARE_TO = '/var/lib/openqa/db/qubes_base_jobs.json'

API_BASE = 'https://openqa.qubes-os.org/api/v1'

args = None

# list of test groups to automatically restart a job if fails
# 'shutdown' is added only to system_tests_update and is needed to upload disk image
RESTART_ON_GROUP_FAIL = ('startup_fixup', 'whonix_firstrun', 'update', 'shutdown')
RESTART_LIMIT = 3

job_restarts = collections.defaultdict(lambda: 0)

def maybe_restart_failed_job(job_id, job_details):
    """Restart failed job if the failure most likely is caused by openQA
       unusual environment. Returns True if the job was restarted"""
    restart = False
    if job_details['job']['result'] == 'user_cancelled':
        return False
    for group in job_details['job']['testresults']:
        if group['result'] in ('passed', 'cancelled', 'none'):
            continue
        if group['name'] not in RESTART_ON_GROUP_FAIL:
            continue
        restart = True
    if not restart:
        return False

    restart_id = job_details['job']['settings']['BUILD'] + '_' + job_details['job']['settings']['TEST']
    if job_restarts[restart_id] >= RESTART_LIMIT:
        print('Job {} restarted {} times already, not restarting again'.format(
                  restart_id, job_restarts[restart_id]), file=sys.stderr)
        return False
    job_restarts[restart_id] += 1

    print('Restarting job {} ({})'.format(job_id, restart_id), file=sys.stderr)
    subprocess.call([
        'openqa-client', '--host', API_BASE.partition('/api/')[0],
        'jobs/{}/restart'.format(job_id), 'post'])
    return True

def callback_done(ch, method, properties, body):
    print('received %r, properties %r, body %r' % (
        method.routing_key, properties, body), file=sys.stderr)
    job_data = json.loads(body)
    r = requests.get('{}/jobs/{}/details'.format(API_BASE, job_data['id']))
    if not r.ok:
        print('failed to get job {} info: {}'.format(job_data['id'], r.text), file=sys.stderr)
        return
    job_details = r.json()

    if maybe_restart_failed_job(job_data['id'], job_details):
        return

    # in case of system_tests_update job, start workers only when it finishes,
    # not when it is created
    if job_data['TEST'] == 'system_tests_update' and job_data['result'] == 'passed':
        if args.job_start_callback:
            subprocess.call(args.job_start_callback, shell=True)

    if job_data['remaining'] > 0:
        print('group not done yet', file=sys.stderr)
        return

    version = job_details['job']['settings']['VERSION']

    cmd = ['python3', os.path.join(SCRIPT_DIR, 'github_reporting.py'), '--package-list', args.package_list]
    cmd.extend([
        '--latest',
        '--build', job_data['BUILD'],
        '--flavor', job_data['FLAVOR'],
        '--version', version])
    cmd.extend(['--instability',])

    if job_data['FLAVOR'] == 'qubes-whonix':
        print('Calling: {}'.format(' '.join(cmd)), file=sys.stderr)
        subprocess.call(cmd)

    elif job_data['FLAVOR'] in ('update', 'pull-requests', 'templates', 'kernel'):
        base_job = None
        if os.path.exists(args.jobs_compare_to):
            with open(args.jobs_compare_to) as f:
                base_jobs = json.loads(f.read())
                base_job_key = "{}-{}".format(version, job_data['FLAVOR'])
                if base_job_key in base_jobs:
                    base_job = base_jobs[base_job_key]
                elif version in base_jobs:
                    base_job = base_jobs[version]
        if base_job:
            cmd.extend(['--compare-to-build', str(base_job)])
        print('Calling: {}'.format(' '.join(cmd)), file=sys.stderr)
        subprocess.call(cmd)

def callback_create(ch, method, properties, body):
    job_data = json.loads(body)
    r = requests.get('{}/jobs/{}'.format(API_BASE, job_data['id']))
    if not r.ok:
        print('failed to get job {} info: {}'.format(job_data['id'], r.text), file=sys.stderr)
        return
    job_info = r.json()['job']

    # do not immediately call the callback if jobs are waiting for system_tests_update to finish
    if job_info['settings'].get('START_AFTER_TEST', None) or job_info['settings']['TEST'] == 'system_tests_update':
        return

    if args.job_start_callback:
        subprocess.call(args.job_start_callback, shell=True)

def callback(ch, method, properties, body):
    print(repr(method.routing_key), file=sys.stderr)
    _, event = method.routing_key.rsplit('.', 1)
    if event == 'done':
        callback_done(ch, method, properties, body)
    elif event == 'create':
        callback_create(ch, method, properties, body)

def setup_channel():
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()
    channel.exchange_declare(exchange='pubsub', exchange_type='topic', passive=True, durable=True)
    result = channel.queue_declare('', exclusive=True)
    queue_name = result.method.queue
    binding_keys = ['qubes.openqa.#']
    #binding_keys = ['qubes.openqa.job.done', 'qubes.openqa.job.create']
    for binding_key in binding_keys:
        channel.queue_bind(exchange='pubsub', queue=queue_name, routing_key=binding_key)

    channel.basic_consume(queue=queue_name,
                          auto_ack=True,
                          on_message_callback=callback)
    return channel

def main():
    global args
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--package-list',
        default=DEFAULT_PACKAGE_LIST,
        help="A .json file containing mapping from distribution package names"
             "to Qubes repos.")
    parser.add_argument(
        '--jobs-compare-to',
        default=DEFAULT_JOBS_COMPARE_TO,
        help='A .json file with a base job to compare to for each VERSION')
    parser.add_argument(
        '--job-start-callback',
        help='A command to run when some job is started. Can be used to wake up workers.')

    args = parser.parse_args()
    print(args.package_list, file=sys.stderr)
    print(args.jobs_compare_to, file=sys.stderr)

    channel = setup_channel()

    print('Waiting for messages. To exit press CTRL+C', file=sys.stderr)
    channel.start_consuming()

if __name__ == '__main__':
    main()

