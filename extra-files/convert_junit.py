# -*- encoding: utf-8 -*-
#
# The Qubes OS Project, http://www.qubes-os.org
#
# Copyright (C) 2017 Marek Marczykowski-Górecki
#                               <marmarek@invisiblethingslab.com>
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

from xml.etree import ElementTree
import sys
from collections import OrderedDict

def main():
    testcases = OrderedDict()
    xml_root = ElementTree.parse(sys.argv[1]).getroot()
    for testcase in xml_root.findall('testcase'):
        classname = testcase.get('classname')
        if classname not in testcases:
            testcases[classname] = []
        testcases[classname].append(testcase)

    output_xml = ElementTree.Element('testsuites')
    for classname in testcases:
        category, name = classname.rsplit('.', 1)
        testsuite = ElementTree.Element('testsuite')
        failures = 0
        errors = 0
        skipped = 0
        tests = 0
        time = 0.0
        for testcase in testcases[classname]:
            if testcase.find('error') is not None:
                testcase.set('status', 'error')
                errors += 1
            elif testcase.find('failure') is not None:
                testcase.set('status', 'failure')
                failures += 1
            elif testcase.find('skipped') is not None:
                testcase.set('status', 'skipped')
                skipped += 1
            else:
                testcase.set('status', 'success')
            # xpath support in ElementTree is limited, 'and' not supported
            existing = [e for e in testsuite.findall(
                "./testcase[@classname='{}']".format(classname))
                if e.get('name') == testcase.get('name')]
            if existing:
                existing = existing[0]
                old_status = existing.get('status')
                new_status = testcase.get('status')
                # priority list: error -> failure -> skipped -> success
                for status in ('error', 'failure', 'skipped', 'success'):
                    if status in (old_status, new_status):
                        existing.set('status', status)
                for attr in ('errors', 'failures', 'skipped'):
                    if testcase.get(attr) is not None:
                        # new one can only be '1'
                        old = existing.get(attr) or 0
                        existing.set(attr, str(int(old) + 1))
                for el_name in ('error', 'failure', 'skipped'):
                    for el in testcase.findall(el_name):
                        existing.append(el)
            else:         
                tests += 1
                time += float(testcase.get('time'))
                testsuite.append(testcase)

        testsuite.set('package', str(category.replace('.', '_') + '.' + name))
        testsuite.set('name', str(name))
        testsuite.set('failures', str(failures))
        testsuite.set('errors', str(errors))
        testsuite.set('skipped', str(skipped))
        testsuite.set('tests', str(tests))
        testsuite.set('time', str(time))
        output_xml.append(testsuite)

    with open(sys.argv[2], 'wb') as f:
        for ts in output_xml.findall('testsuite'):
            f.write(ElementTree.tostring(ts))
    #ElementTree.ElementTree(output_xml).write(sys.argv[2])

if __name__ == '__main__':
    main()
