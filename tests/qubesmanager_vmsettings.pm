
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
    my ($self) = @_;

    # open global-settings
    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('qubes-vm-settings work');

    # basic
    assert_screen('vm-settings-correct_current');

    # change label
    assert_and_click('vm-settings-label-open', timeout => 30, clicktime => 0.10);
    assert_and_click('vm-settings-label-click-red');

    # change template
    assert_and_click('vm-settings-template-opened');
    assert_and_click('vm-settings-template-change-whonix');

    # change networking to None
    assert_and_click('vm-settings-networking-opened');
    assert_and_click('vm-settings-networking-change-none');

    # include in backups by default, start on boot
    assert_and_click('vm-settings-autostart');
    assert_and_click('vm-settings-include-in-backup');
    if (check_var('VERSION', '4.0')) {
        # run in debug mode
        send_key('tab');
        send_key('spc');
    }

    # increase storage
    send_key('tab');
    send_key('up');

    # confirm
    assert_and_click('vm-settings-ok');

    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_screen('vm-settings-basics-changed');

    # advanced
    assert_and_click('vm-settings-advanced-tab');
    assert_screen('vm-settings-advanced-check-current');

    # change memory
    assert_and_click('vm-settings-advanced-memory');
    send_key('ctrl-a');
    type_string('50');
    send_key('ret');
    # check if label was shown
    assert_and_click('vm-settings-warn-mem');
    # switch to editing memory
    assert_and_click('vm-settings-click-mem');
    send_key('ctrl-a');
    type_string('600');
    send_key('tab');
    type_string('3000');
    send_key('tab');

    assert_screen('vm-settings-no-warn-mem');

    # change VPUs
    type_string('1');

    # allow starting dispvms
    assert_and_click('vm-settings-allow-dispvms');

    # change default dispvm
    assert_and_click('vm-settings-def-dvm-open');
    assert_and_click('vm-settings-def-dvm-set-none');

    # change kernel
    assert_and_click('vm-settings-kernel-open');
    assert_and_click('vm-settings-kernel-none');

    # virt mode set to hvm
    assert_and_click('vm-settings-virtmode-opened');
    assert_and_click('vm-settings-virtmode-hvm');

    # confirm
    assert_and_click('vm-settings-ok');

    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-advanced-tab');
    assert_screen('vm-settings-advanced-changed');

    # firewall
    assert_and_click('vm-settings-firewall-tab');
    assert_and_click('vm-settings-firewall-warning');

    # add new rule
    assert_and_click('vm-settings-firewall-limit');
    assert_and_click('vm-settings-fw-add-rule');
    type_string('192.168.1.1');
    assert_and_click('vm-settings-fw-tcp', mousehide => -1);
    assert_and_click('vm-settings-service-open');
    assert_and_click('vm-settings-service-http', mousehide => 1);
    send_key('ret');
    assert_screen('vm-settings-fw-set');

    # confirm
    assert_and_click('vm-settings-ok');
    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-firewall-tab');
    assert_and_click('vm-settings-firewall-warning');
    assert_screen('vm-settings-fw-set');

    # devices
    assert_and_click('vm-settings-devices-tab');
    assert_and_click('vm-settings-devices-strict-reset');
    assert_and_click('vm-settings-devices-strict-ok');

    # select a device and add
    if (!check_screen('vm-settings-devices-select', 10)) {
        # if not there, try to scroll first
        assert_and_click('vm-settings-devices-scroll-down');
    }
    assert_and_click('vm-settings-devices-select');
    assert_and_click('vm-settings-devices-add');

    # confirm
    assert_and_click('vm-settings-ok');
    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-devices-tab');
    assert_screen('vm-settings-devices-set');

    # remove device
    assert_and_click('vm-settings-devices-remove-all');
    send_key('alt-o');

    # start again
    x11_start_program('qubes-vm-settings work');

    # applications
    assert_and_click('vm-settings-applications-tab');
    assert_and_click(['vm-settings-apps-dolphin-select', 'vm-settings-apps-thunar-select', 'vm-settings-apps-start-qube-select', 'vm-settings-apps-mousepad-select']);
    assert_and_click('vm-settings-apps-add');

    # confirm
    send_key('alt-o');
    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-applications-tab');
    assert_screen('vm-settings-applications-set');

    # services
    assert_and_click('vm-settings-services-tab');

    # add clocksync
    assert_and_click('vm-settings-services-entry');
    if (check_var('VERSION', '4.0')) {
        type_string('clocksync');
        send_key('ret');
    } else {
        assert_and_click('vm-settings-services-clocksync');
        assert_and_click('vm-settings-services-add');
    }

    # confirm
    send_key('alt-o');
    assert_screen('desktop');

    # check if it worked
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-services-tab');
    assert_screen('vm-settings-services-set');

    # remove clock
    assert_and_click('vm-settings-service-select-clock');
    assert_and_click('vm-settings-service-remove-clock');

    # and done
    assert_and_click('vm-settings-ok');
    assert_screen('desktop');

    # check rename, clone and delete qube
    x11_start_program('qubes-vm-settings work');
    assert_and_click('vm-settings-rename');
    assert_screen('vm-settings-do-rename');
    type_string('work2');
    assert_and_click('vm-settings-do-rename');

    assert_screen('desktop', 120);

    x11_start_program('qubes-vm-settings work2');
    assert_and_click('vm-settings-clone');
    type_string('work3');
    assert_and_click('vm-settings-do-clone');

    assert_and_click('vm-settings-clone-successful', timeout => 200);
    sleep(1);
    assert_and_click('vm-settings-cancel');

    assert_screen('desktop');
    x11_start_program('qubes-vm-settings work2');

    assert_and_click('vm-settings-delete');
    sleep(1);
    type_string('work2');
    assert_and_click('vm-settings-do-delete');

    assert_screen('desktop');

    # check if can cancel
    x11_start_program('qubes-vm-settings work3');
    assert_and_click('vm-settings-rename');
    assert_and_click('vm-settings-rename-cancel');

    assert_and_click('vm-settings-clone');
    assert_and_click('vm-settings-clone-cancel');

    assert_and_click('vm-settings-delete');
    assert_and_click('vm-settings-delete-cancel');

    assert_and_click('vm-settings-cancel');

    assert_screen('desktop');

}

sub post_fail_hook {
    my ($self) = @_;
    send_key('esc');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

