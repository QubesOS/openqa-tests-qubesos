
# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2019 Marta Marczykowska-Górecka <marmarta@invisiblethingslab.com>
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

use base "installedtest";
use strict;
use testapi;


sub run {
    # open global-settings
    select_console('x11');
    assert_screen "desktop";
    x11_start_program('qubes-qube-manager');

    # sort by template
    assert_and_click('qube-manager-sort-template', timeout => 5);

    # right-click on a non-dom0 vm
    assert_and_click('qube-manager-vm-rc', button => 'right', timeout => 5);
    assert_screen('qube-manager-rclicked', 5);
    send_key("esc");

    # check if dom0 logs are not empty
    assert_and_click('qube-manager-dom0-rc', button => 'right', timeout => 5);
    if (check_var("VERSION", "4.0")) {
        # Qubes 4.0: logs submenu
        # clicking over this menu is sensitive for mouse movements and
        # unfortunately assert_and_click insists on moving mouse back to the
        # original possition
        assert_screen('qube-manager-dom0-logs', 5);
        send_key("up");
        send_key("right");
        assert_screen('qube-manager-dom0-logs2', 10);
        send_key("esc");
        send_key("esc");
    } else {
        # Qubes 4.1+: logs dialog
        assert_and_click('qube-manager-dom0-logs');
        assert_screen('qube-manager-dom0-logs-window');
        send_key('esc');
    }

    # exit politely, also checking if menus click
    assert_and_click('qube-manager-system-open', timeout => 10);
    assert_and_click('qube-manager-system-exit', timeout => 10);

}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

