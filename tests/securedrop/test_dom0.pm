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
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use base "installedtest";
use strict;
use testapi;
use networking;
use serial_terminal qw(select_root_console);

sub run {
    my ($self) = @_;

    $self->select_gui_console;

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    # HACK: work around "extra-files" failing to be obtained via the usual route (via CASEDIR b64)
    assert_script_run("qvm-run -p sd-dev 'curl https://raw.githubusercontent.com/QubesOS/openqa-tests-qubesos/refs/heads/main/extra-files/convert_junit.py 2>/dev/null' > /home/user/convert_junit.py");

    my $sdw_path = "/home/user/securedrop-workstation";

    # Setup testing requirements and run tests
    assert_script_run('rpm -q python3-pytest || sudo qubes-dom0-update -y python3-pytest', timeout => 300);
    assert_script_run('rpm -q python3-pytest-cov || sudo qubes-dom0-update -y python3-pytest-cov', timeout => 300);
    script_run('ln -s /usr/share/securedrop-workstation-dom0-config/config.json /home/user/securedrop-workstation/config.json');
    script_run('ln -s /usr/share/securedrop-workstation-dom0-config/sd-journalist.sec /home/user/securedrop-workstation/sd-journalist.sec');
    script_run("env CI=true make -C $sdw_path test | tee make-test.log", timeout => 2400);


    curl_via_netvm; # necessary for upload_logs
    upload_logs("$sdw_path/test-data.xml", failok => 1);  # Upload original (in case conversion fails)

    script_run("iconv -f utf8 -t ascii//translit $sdw_path/test-data.xml > $sdw_path/test-data-tmp.xml");
    script_run("python3 /home/user/convert_junit.py $sdw_path/test-data-tmp.xml $sdw_path/test-data-converted.xml");
    script_run("head $sdw_path/test-data-converted.xml");

    parse_junit_log("$sdw_path/test-data-converted.xml");

};


sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();

    # make test: upload also original xml, if something goes wrong with conversion
    upload_logs("/home/user/securedrop-workstation/test-data.xml", failok => 1);
    upload_logs("/home/user/securedrop-workstationtest-data-converted.xml", failok => 1);

};


1;
