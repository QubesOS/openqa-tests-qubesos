#!/usr/bin/python3

import os.path
import pika
import json
import argparse
import requests
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
DEFAULT_PACKAGE_LIST = os.path.join(SCRIPT_DIR, 'github_package_mapping.json')
DEFAULT_JOBS_COMPARE_TO = '/var/lib/openqa/db/qubes_base_jobs.json'

API_BASE = 'https://openqa.qubes-os.org/api/v1/'

args = None

def callback_done(ch, method, properties, body):
    print('received done, properties %r, body %r' % (
        properties, body))
    job_data = json.loads(body)
    if job_data['remaining'] > 0:
        print('group not done yet done')
        return
    r = requests.get('{}/jobs/{}'.format(API_BASE, job_data['id']))
    if not r.ok:
        print('failed to get job {} info: {}'.format(job_data['id'], r.text))
        return
    job_details = r.json()

    version = job_details['job']['settings']['VERSION']

    cmd = ['python3', os.path.join(SCRIPT_DIR, 'github_reporting.py'), '--package-list', args.package_list]
    cmd.extend(['--latest', '--build', job_data['BUILD']])

    if job_data['FLAVOR'] == 'qubes-whonix':
        subprocess.call(cmd)

    elif job_data['FLAVOR'] == 'update':
        base_job = None
        if os.path.exists(args.jobs_compare_to):
            with open(args.jobs_compare_to) as f:
                base_jobs = json.loads(f.read())
                if version in base_jobs:
                    base_job = base_jobs[version]
        if base_job:
            cmd.extend(['--compare-to-job', str(base_job)])
        subprocess.call(cmd)


def setup_channel():
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()
    channel.exchange_declare(exchange='pubsub', exchange_type='topic', passive=True, durable=True)
    result = channel.queue_declare('', exclusive=True)
    queue_name = result.method.queue
    binding_keys = ['qubes.openqa.job.done']
    for binding_key in binding_keys:
        channel.queue_bind(exchange='pubsub', queue=queue_name, routing_key=binding_key)

    channel.basic_consume(queue=queue_name,
                          auto_ack=True,
                          on_message_callback=callback_done)
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

    args = parser.parse_args()
    print(args.package_list)
    print(args.jobs_compare_to)

    channel = setup_channel()

    print('Waiting for messages. To exit press CTRL+C')
    channel.start_consuming()

if __name__ == '__main__':
    main()

