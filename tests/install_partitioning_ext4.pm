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

use base 'anacondatest';
use strict;
use testapi;

sub run {
    my $luks_set = 0;
    assert_and_click 'installer-main-hub-target';
    assert_screen 'installer-disk-spoke';
    assert_and_click 'installer-disk-custom-partitioning';
    assert_and_click 'installer-done';
    assert_screen ['installer-disk-luks-passphrase', 'installer-custom-partitioning'];
    if (match_has_tag('installer-disk-luks-passphrase')) {
        type_string 'lukspass';
        send_key 'tab';
        type_string 'lukspass';
        send_key 'ret';
        $luks_set = 1;
    }
    assert_screen 'installer-custom-partitioning';
    # TODO: this may be language dependent
    send_key 'alt-n';
    send_key_until_needlematch('install-custom-type-lvm', 'up', 5, 1);
    send_key 'shift-tab';
    send_key 'ret';
    save_screenshot;
    if (!check_var("VERSION", "4.0")) {
        # R4.1+
        assert_and_click 'install-custom-standard-varlibqubes';
        assert_and_click 'install-custom-fstype';
        assert_and_click 'install-custom-fstype-ext4';
        assert_and_click 'install-custom-fstype-update';
    }
    assert_and_click 'installer-done';
    assert_screen ['installer-disk-luks-passphrase', 'installer-custom-summary-accept'];
    if (match_has_tag('installer-disk-luks-passphrase')) {
        type_string 'lukspass';
        send_key 'tab';
        type_string 'lukspass';
        send_key 'ret';
        $luks_set = 1;
    }
    assert_and_click 'installer-custom-summary-accept';
    assert_screen 'installer-main-hub';
    die "LUKS passphrase not prompted" unless $luks_set;
}

1;

# vim: set sw=4 et:
