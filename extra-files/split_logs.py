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
import os
import re

def get_logs(path):
    logs = {} # filename -> lines[]
    for file_name in os.listdir(path):
        if not file_name.startswith("guest-test-"):
            continue
        with open(path + file_name, 'r') as f:
            logs[file_name] = f.readlines()
    return logs

def filter_logs_by_time(logs, start_time, end_time):
    filtered_logs = {} # filename -> lines[]
    timestamp_re = r'[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'

    def line_in_scope(line):
        timestamp_match = re.search(timestamp_re, line)
        if timestamp_match is None:
            return False
        else:
            timestamp = datetime.datetime.fromisoformat(
                timestamp_match.group(0))
            return start_time <= timestamp <= end_time

    for log in logs:
        lines = logs[log]
        lines_to_keep = list(filter(line_in_scope, lines))
        if len(lines_to_keep) > 0:
            filtered_logs[log] = lines_to_keep

    return filtered_logs

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

    for testsuite_xml in testsuites_XMLs:
        xml = minidom.parseString(testsuite_xml)
        logs = get_logs(args.xen_logs)

        testcases = xml.getElementsByTagName('testcase')
        for testcase in testcases:
            status = testcase.attributes['status'].value
            if status in ["success", "skipped"]:
                continue
            name  = testcase.attributes['classname'].value
            title = testcase.attributes['name'].value
            title_short = re.match(r'test_[0-9]*', title).group(0)

            time = datetime.timedelta(
                seconds=float(testcase.attributes['time'].value))
            timestamp_str = testcase.attributes['timestamp'].value
            start_time = datetime.datetime.fromisoformat(timestamp_str)
            end_time = start_time + time

            testcase_logs = filter_logs_by_time(logs, start_time, end_time)
            for log_name in testcase_logs:
                lines = testcase_logs[log_name]
                log_filename = "{}.{}.{}".format(name, title_short, log_name)
                with open(args.outdir + log_filename, 'w') as f:
                    f.writelines(lines)

if __name__ == '__main__':
    main()
