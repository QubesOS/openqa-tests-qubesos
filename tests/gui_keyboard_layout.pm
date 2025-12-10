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
    my ($self, $guivm) = @_;
    # touch a file with input from gui domain and then from target vm
    x11_start_program('touch e1qwertya', valid => 0);
    x11_start_program('qvmrun work xterm', target_match => ['work-xterm', 'work-xterm-inactive', 'whonix-wizard-cancel', 'whonix-systemcheck-error'], match_timeout => 90);
    if ($self->{template} =~ /whonix/) {
        # wait for possibly whonixcheck...
        sleep 5;
        if (check_screen('whonix-wizard-cancel', 5)) {
            click_lastmatch();
        }
        # and a message about wrong qube type
        if (check_screen('whonix-systemcheck-error', 20)) {
            click_lastmatch();
        }
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
    $self->select_gui_console;
}

sub switch_layout {
    my ($self, $layout) = @_;

    if (check_var("DESKTOP", "kde")) {
        # compare with LayoutList config set in run()
        my $layout_idx;
        $layout_idx = 0 if ($layout eq "us");
        $layout_idx = 1 if ($layout eq "de");
        die "unsupported layout $layout" unless defined $layout_idx;
        x11_start_program("gdbus call -e -d org.kde.keyboard -o /Layouts -m org.kde.KeyboardLayouts.setLayout $layout_idx", valid => 0);
    } else {
        x11_start_program("setxkbmap $layout", valid => 0);
    }
}


sub test_layout {
    my ($self, $guivm) = @_;

    # set keyboard layout before VM start
    record_info('Layout: de', 'Switching keyboard layout before VM start');
    $self->switch_layout("de");
    sleep 1;

    $self->test_file_touch($guivm);

    record_info('Layout: us', 'Switching keyboard layout after VM start');
    $self->switch_layout("us");
    sleep 1;

    if (!check_var('VERSION', '4.0')) {
        $self->test_file_touch($guivm);
    }
}

sub run {
    my ($self) = @_;

    # assert clean initial state
    $self->select_gui_console;

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

    if (check_var("DESKTOP", "kde")) {
        # https://euroquis.nl/kde/2024/09/14/keyboard.html
        if ($guivm eq 'dom0') {
            my $ret = script_run("sudo -u user sed -i -e 's/LayoutList=.*/LayoutList=us,de/' /home/user/.config/kxkbrc");
            if ($ret != 0) {
                assert_script_run("echo -e '[Layout]\nLayoutList=us,de' | sudo -u user tee /home/user/.config/kxkbrc");
            }
            assert_script_run("sudo -u user env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gdbus emit -e -o /Layouts -s org.kde.keyboard.reloadConfig");
        } else {
            # TODO: do the above via qvm-run
            die "not implemented"
        }
    }

    foreach (split /\n/, $templates) {
        next unless /Template/;
        s/\|.*//;
        my $template = $_;

        select_root_console();
        # wait for it to finish starting first
        assert_script_run("qvm-run -pu root work systemctl --wait is-system-running");
        assert_script_run("qvm-shutdown --wait work");
        record_info($template, "Switching work qube to $template");
        assert_script_run("qvm-prefs work template $template");
        if ($template =~ /whonix-g/) {
            # avoid complains about wrong qube type
            assert_script_run("qvm-prefs work provides_network true");
        } else {
            assert_script_run("qvm-prefs -D work provides_network");
        }
        $self->select_gui_console;
        $self->{template} = $template;

        $self->test_layout($guivm);
    }
    $self->select_gui_console;
}

sub post_fail_hook {
    my ($self) = @_;
    $self->select_gui_console;
    save_screenshot;
    $self->SUPER::post_fail_hook;
    $self->save_and_upload_log('qvm-prefs dom0', 'qvm-prefs-dom0.log');
    if (get_var('GUIVM')) {
        $self->save_and_upload_log('qvm-prefs sys-gui', 'qvm-prefs-sys-gui.log');
    }

};

1;

# vim: set sw=4 et:

