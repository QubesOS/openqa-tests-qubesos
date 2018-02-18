# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

package anacondatest;
use base 'basetest';
use strict;
use testapi;

sub post_fail_hook {

    select_console('install-shell');
    type_string "export SYSTEMD_PAGER=\n";
    type_string "if ls /tmp/anaconda-tb-*; then\n";
    type_string "  cat /tmp/anaconda-tb-* >/dev/$serialdev\n";
    type_string "else\n";
    type_string "  ls -l /tmp /var/log >/dev/$serialdev\n";
    type_string "  tail -n 20 /tmp/*.log >/dev/$serialdev\n";
    type_string "  journalctl -b >/dev/$serialdev\n";
    type_string "fi\n";
    sleep 2;
    save_screenshot;

};

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

1;
