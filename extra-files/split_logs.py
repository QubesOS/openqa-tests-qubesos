# -*- encoding: utf-8 -*-
#
# The Qubes OS Project, http://www.qubes-os.org
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

from xml.dom import minidom
import datetime
import argparse
import subprocess
import os
import re

# format for strptime to use instead of datetime.datetime.fromisoformat()
ISOFORMAT = '%Y-%m-%dT%H:%M:%S.%f'
XENLOGFORMAT = '%Y-%m-%d %H:%M:%S'

def get_logs(path):
    logs = {} # filename -> lines[]
    for file_name in os.listdir(path):
        if not file_name.startswith("guest-test-"):
            continue
        with open(os.path.join(path, file_name), 'r') as f:
            logs[file_name] = f.readlines()
    return logs

def get_timestamp_from_xen_logs(log_line):
    timestamp_re = r'[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
    timestamp_match = re.search(timestamp_re, log_line)
    if timestamp_match is None:
        return None
    else:
        return datetime.datetime.strptime(
            timestamp_match.group(0),
            XENLOGFORMAT)

def get_timestamp_from_journalctl(log_line):
    timestamp_re = r'(Jan|Feb|Mar|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'\
        ' [0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
    timestamp_match = re.search(timestamp_re, log_line)
    if timestamp_match is None:
        return None
    else:
        timestamp_str = timestamp_match.group(0)
        timestamp = datetime.datetime.strptime(timestamp_str, "%b %d %H:%M:%S")

        # journalctl logs are missing year data, thus we assume the present year
        # WARNING: may break around the new year!
        utc_now = datetime.datetime.utcnow()
        return timestamp.replace(year=utc_now.year)

def filter_logs_by_time(logs, start_time, end_time, dom0_timezone):
    filtered_logs = {} # filename -> lines[]

    def line_in_scope(line):
        timestamp = get_timestamp_from_xen_logs(line)
        if timestamp is None:
            return False
        else:
            timestamp = timestamp.replace(tzinfo=dom0_timezone)
            return start_time <= timestamp <= end_time

    for log in logs:
        lines = logs[log]
        lines_to_keep = list(filter(line_in_scope, lines))
        if len(lines_to_keep) > 0:
            filtered_logs[log] = lines_to_keep

    return filtered_logs

def get_time_offset(test_name, test_title, utc_timestamp):
    journalctl_line = subprocess.check_output(
        "sudo journalctl -r | grep -m 1 \"{}.{}\"".format(test_name, test_title),
        shell=True).decode('ascii')
    journalctl_timestamp = get_timestamp_from_journalctl(journalctl_line)

    # allow comparison between offset-naive and offset-aware datetimes
    utc_timestamp = utc_timestamp.replace(tzinfo=None, microsecond=0)
    return datetime.timezone(journalctl_timestamp - utc_timestamp)

def main():
    parser = argparse.ArgumentParser(description='Process some integers.')
    parser.add_argument('--junit-xml', required=True,
                        help='Junit XML file containing test data.')
    parser.add_argument('--xen-logs',
                        default='/var/log/xen/console',
                        help='Where /var/log/xen/console is located\
                            (useful for testing in dev vm).')
    parser.add_argument('--outdir', required=True,
                        help='Where to output the split logs.')

    args = parser.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    with open(args.junit_xml, 'r') as f:
        # split XML since nose2 malformats XML with multiple different root
        # elements.
        testsuites_XMLs = re.findall(r"(<testsuite.*?</testsuite>)",
                                     f.read(), re.DOTALL)
    dom0_timezone = None

    for testsuite_xml in testsuites_XMLs:
        xml = minidom.parseString(testsuite_xml)
        logs = get_logs(args.xen_logs)

        testcases = xml.getElementsByTagName('testcase')
        for testcase in testcases:
            status = testcase.attributes['status'].value
            if status in ["success", "skipped"]:
               continue
            test_name  = testcase.attributes['classname'].value
            test_title = testcase.attributes['name'].value
            test_title_short = re.match(r'test_[0-9]*', test_title).group(0)

            time = datetime.timedelta(
                seconds=float(testcase.attributes['time'].value))
            test_start = datetime.datetime.strptime(
                                      testcase.attributes['timestamp'].value,
                                      ISOFORMAT)\
                                     .replace(tzinfo=datetime.timezone.utc)
            test_end = test_start + time

            # timestamp zero in epoch time is an exception. See:
            # https://github.com/nose-devs/nose2/pull/505/commits/fdd17f6
            date_exception = datetime.datetime.utcfromtimestamp(0)\
                                     .replace(tzinfo=datetime.timezone.utc)
            if test_start == date_exception:
                continue

            if dom0_timezone is None:
                dom0_timezone = get_time_offset(test_name, test_title,
                                                test_start)
            testcase_logs = filter_logs_by_time(logs, test_start, test_end,
                                                dom0_timezone)
            for log_name in testcase_logs:
                lines = testcase_logs[log_name]
                log_filename = "{}.{}.{}".format(
                    test_name, test_title_short, log_name)
                with open(args.outdir + log_filename, 'w') as f:
                    f.writelines(lines)

if __name__ == '__main__':
    main()
