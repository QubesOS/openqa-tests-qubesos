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

sub run {
    my ($self) = @_;

    $self->select_gui_console;

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    # under some circumstances sd-proxy may be powered off
    assert_script_run('qvm-start sd-proxy --skip-if-running');

    # # Close login window (next step opens it already)
    # send_key('alt-f4');

    script_run("make -C securedrop-workstation/ run-client");
    sleep(60); # Wait for login

    assert_screen("fail-here");

};

1;
