
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
    select_console('x11');
    assert_screen "desktop";

    # workaround for GTK+ setting too large window under XFCE
    x11_start_program("gsettings set org.gtk.Settings.FileChooser window-size '(800, 600)'", valid => 0);
    x11_start_program("gsettings set org.gtk.Settings.FileChooser window-position '(50, 50)'", valid => 0);

    prep_backup('dom0', 1);
    assert_and_click('backup-next', timeout => 5);

    # cancel the backup
    assert_and_click('backup-cancel', timeout => 15);
    assert_screen('backup-cancelled', 30);
    send_key('esc');
    send_key('esc');

    assert_screen('desktop', 60);

    # retry backup
    prep_backup('dom0', 0);
    assert_and_click('backup-next', timeout => 5);
    assert_and_click('backup-finish', timeout => 120);

    assert_screen('desktop', 60);

    do_restore();

    assert_screen('desktop', 60);

    # and now just check if restore is able to cancel
    x11_start_program('qubes-backup-restore');

    assert_and_click('restore-cancel', timeout => 15);

    assert_screen('desktop');


}

sub prep_backup {
    my $vmname = $_[0];
    my $bigger = $_[1];
    x11_start_program('qubes-backup');

    # move all vms to unavailable
    assert_and_click('backup-deselect-all', timeout => 15);
    assert_screen('backup-selected-none');

    # select only sys-net
    assert_and_click('backup-select-sys-net', timeout => 15);
    assert_and_click('backup-select-sys-net2', timeout => 15);

    # select some template too
    if ($bigger) {
        assert_and_click('backup-select-bigger', timeout => 15);
        assert_and_click('backup-select-sys-net2', timeout => 15);
    }

    # click next
    assert_and_click('backup-next', timeout => 10);

    if ($vmname eq 'sys-net') {
        send_key('s');
        send_key('s');
    } else {
        send_key('d');
    }
    send_key('tab');

    assert_and_click('backup-select-backup-dir', timeout => 10);
    sleep(5); # needed because if the window appears too slowly, the ~ is ignored
    send_key('~');
    send_key('ret');
    #assert_and_click('backup-select-backup-dir3', timeout => 10);
    sleep(5); # as above

    # input password
    send_key('tab');
    send_key('tab');
    send_key('a');
    send_key('tab');
    send_key('a');

    assert_and_click('backup-next', timeout => 10);
    assert_screen('backup-confirmation-screen', 10);

}

sub do_restore {
    x11_start_program('qubes-backup-restore');

    # make sure dom0 is selected
    send_key('d');

    assert_and_click('restore-select', timeout => 15);
    send_key('~');
    send_key('ret');
    assert_screen(['select-file-is-home', 'select-file-home']);
    if (match_has_tag('select-file-home')) {
        click_lastmatch();
    }
    assert_and_click('select-file-sort-modified', timeout => 15);
    assert_and_click('restore-select-file', timeout => 15);
    send_key('end');

    send_key('ret');

    assert_and_click('restore-verify-only', timeout => 15);

    # password input
    send_key('tab');
    send_key('tab');
    send_key('tab');

    send_key('a');

    # wait for app to register passphrase
    sleep(1);

    assert_and_click('restore-next', timeout => 15);

    assert_and_click('restore-select-all', timeout => 15);
    assert_and_click('restore-next', timeout => 15);

    # view the summary screen and go forward
    assert_and_click('restore-next', timeout => 15);

    # wait for success
    assert_and_click('restore-success', timeout => 90);

    # exit
    assert_and_click('restore-finish', timeout => 10);
    
    send_key('esc');
}

sub post_fail_hook {
    my ($self) = @_;
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;
};

1;

# vim: set sw=4 et:

