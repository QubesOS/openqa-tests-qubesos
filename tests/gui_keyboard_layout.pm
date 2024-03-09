# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
use serial_terminal;

=head2

    test_file_touch($guivm)

Touch a file in GUI VM (which can be dom0) and 'work' VM and compare if entered
name matches.

Uses 'qwertya' string, as 'y' and 'a' positions differ in some layout (us, de, fr).

=cut
sub test_file_touch {
    my ($guivm) = @_;
    # touch a file with input from gui domain and then from target vm
    x11_start_program('touch e1qwertya', valid => 0);
    x11_start_program('qvmrun work xterm', target_match => ['work-xterm', 'work-xterm-inactive', 'whonix-wizard-cancel'], match_timeout => 90);
    # wait for possibly whonixcheck...
    sleep 5;
    if (check_screen('whonix-wizard-cancel', 5)) {
        click_lastmatch();
    }
    # and a message about wrong qube type
    if (check_screen('whonix-systemcheck-error', 20)) {
        click_lastmatch();
    }
    # ... then click xterm again
    assert_and_click(['work-xterm', 'work-xterm-inactive']);
    type_string("touch e1qwertya\n");
    sleep 1;
    save_screenshot;
    type_string("exit\n");
    sleep 1;
    select_root_console();
    assert_script_run('set -x');
    if ($guivm eq 'dom0') {
        assert_script_run('test "$(cd ~user;ls e1*)" = "$(qvm-run -p work \'ls e1*\')"');
        assert_script_run('rm -f ~user/e1*; qvm-run -p work \'rm -f e1*\'');
    } else {
        assert_script_run('test "$(qvm-run --nogui -p ' . $guivm . ' \'ls e1*\')" = "$(qvm-run -p work \'ls e1*\')"');
        assert_script_run('qvm-run --nogui -p ' . $guivm . ' \'rm -f e1*\'; qvm-run -p work \'rm -f e1*\'');
    }
    assert_script_run('set +x');
    select_console('x11');
}

sub test_layout {
    my ($guivm) = @_;

    # set keyboard layout before VM start
    record_info('Layout: de', 'Switching keyboard layout before VM start');
    x11_start_program('setxkbmap de', valid => 0);
    sleep 1;

    test_file_touch($guivm);

    record_info('Layout: us', 'Switching keyboard layout after VM start');
    x11_start_program('setxkbmap us', valid => 0);
    sleep 1;

    if (!check_var('VERSION', '4.0')) {
        test_file_touch($guivm);
    }
}

sub run {
    # assert clean initial state
    select_console('x11');

    assert_screen "desktop";

    select_root_console();
    # '-' is in different place on 'de' keyboard, make a symlink to avoid it
    my $templates = script_output('qvm-ls --raw-data --fields name,klass');
    my $guivm = script_output('qubes-prefs default-guivm 2>/dev/null || echo dom0');
    if ($guivm eq 'dom0') {
        assert_script_run("ln -s /usr/bin/qvm-run /usr/local/bin/qvmrun");
    } else {
        # make qvm-run work for arbitrary commands too
        assert_script_run("echo 'qubes.VMShell * $guivm \@tag:guivm-$guivm allow' >> /etc/qubes/policy.d/25-tests.policy");
        assert_script_run("echo 'qubes.VMExec * $guivm \@tag:guivm-$guivm allow' >> /etc/qubes/policy.d/25-tests.policy");
        assert_script_run("echo 'qubes.VMExecGUI * $guivm \@tag:guivm-$guivm allow' >> /etc/qubes/policy.d/25-tests.policy");
        assert_script_run("qvm-run -u root --nogui $guivm 'ln -s /usr/bin/qvm-run /usr/local/bin/qvmrun'");
    }
    foreach (split /\n/, $templates) {
        next unless /Template/;
        s/\|.*//;
        my $template = $_;

        select_root_console();
        assert_script_run("qvm-shutdown --wait work");
        record_info($template, "Switching work qube to $template");
        assert_script_run("qvm-prefs work template $template");
        select_console('x11');

        test_layout($guivm);
    }
    select_console('x11');
}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    save_screenshot;
    $self->SUPER::post_fail_hook;
    $self->save_and_upload_log('qvm-prefs dom0', 'qvm-prefs-dom0.log');
    if (get_var('GUIVM')) {
        $self->save_and_upload_log('qvm-prefs sys-gui', 'qvm-prefs-sys-gui.log');
    }

};

1;

# vim: set sw=4 et:

