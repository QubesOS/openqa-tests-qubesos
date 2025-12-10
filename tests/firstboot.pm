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

use base "installedtest";
use strict;
use testapi;
use networking;
use utils qw(us_colemak assert_screen_with_keypress);
use bootloader_setup;

my $configuring = 0;

sub setup_user {
    assert_and_click 'installer-install-hub-user';
    assert_screen 'installer-user';
    type_string 'user';
    send_key 'tab';
    if (!check_var('VERSION', '4.1')) {
        send_key 'tab';
    }
    type_string $password;
    send_key 'tab';
    type_string $password;
    # let the password quality check process it
    sleep(1);
    send_key 'f12';
    assert_screen 'installer-user-weak-pass';
    send_key 'f12';
    assert_screen 'installer-install-user-created';
}

sub run {
    my ($self) = @_;

    if (check_var('SKIP_INSTALL', '1')) {
        return;
    }

    if (check_var('HEADS', '1')) {
        heads_boot_default;
    } elsif (!check_var('UEFI', '1')) {
        # wait for bootloader to appear
        assert_screen "bootloader", 90;

        if (match_has_tag("bootloader-installer")) {
            # troubleshooting
            send_key "down";
            send_key "ret";
            # boot from local disk
            send_key "down";
            send_key "down";
            send_key "down";
            send_key "down";
            send_key "ret";
        }
    }

    my @luks_needles = ("luks-prompt", "firstboot-not-ready");
    if (check_var('BACKEND', 'generalhw')) {
        push(@luks_needles, "plymouth-text-no-prompt");
        if (check_var('HEADS', '1') and !check_var("HEADS_DISK_UNLOCK", "1")) {
            # "plymouth-text-no-prompt" would be whole blank here, so fallback
            # to the old approach with check_screen timeout
            if (!check_screen(\@luks_needles, 180)) {
                # force plymouth to show on HDMI output too
                send_key 'esc';
                send_key 'esc';
                sleep 5;
            }
        }
    }

    # handle both encrypted and unencrypted setups
    assert_screen(\@luks_needles, 300);

    if (check_var('BACKEND', 'generalhw')) {
        # disconnect storage function when not needed anymore, so usbguard in
        # dom0 doesn't reject other functions (keyboard, mouse)
        eject_cd;
        sleep(5);
    }

    if (match_has_tag("plymouth-text-no-prompt")) {
        # force plymouth to show on HDMI output too
        send_key 'esc';
        send_key 'esc';
        sleep 5;
    }
    # handle both encrypted and unencrypted setups
    assert_screen(["luks-prompt", "firstboot-not-ready"], 60);

    if (match_has_tag('luks-prompt')) {
        if (check_var("HEADS_DISK_UNLOCK", "1")) {
            die "Unexpected LUKS prompt - should be avoided by keyfile from Heads";
        }
        type_string "lukspass";
        send_key "ret";
    }

    assert_screen "firstboot-not-ready", 180;

    # libinput creates a virtual subdevice on a first tablet move event,
    # and it takes long enough that some events immediately after that
    # might get ignored. Avoid the issue by sending first move in a
    # controlled way and waiting a bit to let it initialize.
    mouse_set(100, 100);
    mouse_click();
    sleep(1);
    mouse_hide;
    sleep(1);

    assert_and_click "firstboot-qubes";

    assert_screen('firstboot-config');

    if (!check_var("VERSION", "4.0")) {
        unless (check_var('INSTALL_TEMPLATES', 'all')) {
            if (index(get_var('INSTALL_TEMPLATES'), 'fedora') == -1) {
                assert_and_click('disable-install-fedora', timeout => 5);
            }
            if (index(get_var('INSTALL_TEMPLATES'), 'debian') == -1) {
                assert_and_click('disable-install-debian', timeout => 5);
            }
            if (index(get_var('INSTALL_TEMPLATES'), 'whonix') == -1) {
                assert_and_click('disable-install-whonix', timeout => 5);
            }
        }
        if (get_var('DEFAULT_TEMPLATE') and !check_var('DEFAULT_TEMPLATE', 'fedora')) {
            assert_and_click('firstboot-default-template');
            if (check_var('DEFAULT_TEMPLATE', 'debian')) {
                assert_and_click('firstboot-default-template-debian');
            } else {
                die "Unsupported default template";
            }
        }
    }

    if (check_var('USBVM', 'none')) {
        # expect checkbox to be enabled by default and disable it
        if (!check_var('BACKEND', 'generalhw') and !check_var('HDDMODEL', 'usb-storage')) {
            # FIXME: make USB HID work with sys-usb out of the box
            assert_and_click('firstboot-qubes-usbvm-enabled', timeout => 5);
        } else {
            assert_screen('firstboot-qubes-usbvm-unavailable', timeout => 5);
        }
    } elsif (check_var('USBVM', 'disable')) {
        # "disable" differs from "none" by not expecting it to be disabled
        # automatically, but to disable it explicitly
        assert_and_click('firstboot-qubes-usbvm-enabled', timeout => 5);
    } elsif (get_var('USBVM', 'sys-usb') eq 'sys-usb') {
        assert_screen('firstboot-qubes-usbvm-enabled', 5);
        if (check_var('BACKEND', 'generalhw') && !check_var('HID', 'PS2')) {
            assert_screen('firstboot-qubes-usb-keyboard-allowed');
            assert_and_click('firstboot-qubes-usb-mouse-allow');
        } elsif (check_var('HID', 'PS2')) {
            assert_screen('firstboot-qubes-usb-keyboard-not-allowed');
        }
    } elsif (check_var('USBVM', 'sys-net')) {
        assert_screen('firstboot-qubes-usbvm-enabled', 5);
        assert_and_click('firstboot-qubes-usbvm-combine', timeout => 5);
    }
    if (check_var('WHONIX_UPDATEVM', '1')) {
        assert_and_click('firstboot-qubes-whonix-updatevm');
    }
    # TODO: check defaults, select various options

    send_key "f12";

    if (check_var("INSTALL_OEM", "1")) {
        setup_user;
    }

    my $needs_to_confirm_done = 1;
    assert_screen(["firstboot-done", "firstboot-in-progress"], 20);
    if (match_has_tag("firstboot-done")) {
        send_key "f12";
        $needs_to_confirm_done = 0;
    }

    $configuring = 1;

    assert_screen "firstboot-configuring-templates", 90;
	
    my $timeout = 900;
    if (check_var('INSTALL_TEMPLATES', 'all')) {
        $timeout *= 4;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /whonix/) {
        $timeout += 2 * 900;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /debian/) {
        $timeout += 1 * 900;
    }
    $timeout *= get_var('TIMEOUT_SCALE', 1);
    assert_screen_with_keypress "firstboot-configuring-salt", $timeout;
    assert_screen_with_keypress "firstboot-setting-network", 600;
    if ($needs_to_confirm_done) {
        assert_screen("firstboot-done", 240);
        send_key "f12";
    } else {
        assert_screen "login-prompt-user-selected", 300;
    }

    assert_screen "login-prompt-user-selected", 90;
    $self->init_gui_session;

    if (check_var('BACKEND', 'generalhw')) {
        # wait for the post-setup service to finish
        sleep 60;
    }
    $self->usbvm_fixup;
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { fatal => 1, milestone => 1 };
}

sub post_fail_hook {
    my $self = shift;

    if ($configuring) {
        send_key "ret";
        sleep 2;
        send_key "f12";

        check_screen "login-prompt-user-selected", 30;
        $self->SUPER::post_fail_hook();
    }
};

1;

# vim: set sw=4 et:
