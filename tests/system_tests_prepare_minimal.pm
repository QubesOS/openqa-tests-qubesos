# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2024 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    my $tests = get_var("SYSTEM_TESTS");
    my ($packages, $packages_debian, $packages_fedora) = ("", "", "");
    my ($commands, $commands_debian, $commands_fedora) = ("");
    if ($tests =~ m/extra/) {
        if (get_var("QUBES_TEST_EXTRA_INCLUDE") =~ m/usbproxy/) {
            $packages = "qubes-usb-proxy";
        } elsif (get_var("QUBES_TEST_EXTRA_EXCLUDE")) {
            # this is the "all other" extra tests, including QVC, install it
            $packages = "qubes-video-companion";
        }
    } elsif ($tests =~ m/dom0_update/) {
        $packages = "qubes-core-agent-dom0-updates qubes-core-admin-client qubes-repo-templates";
    } elsif ($tests =~ m/grub/) {
        $packages_debian = "qubes-kernel-vm-support grub-common grub-pc-bin grub-efi-amd64-bin linux-image-amd64";
        $packages_fedora = "qubes-kernel-vm-support grub2-tools kernel-core";
        $commands_fedora = "grub2-install /dev/xvda";
        $commands_debian = "grub-install /dev/xvda";
    } elsif ($tests =~ m/network/) {
        $packages_fedora = "qubes-core-agent-networking qubes-core-agent-network-manager network-manager-applet ping procps-ng";
        $packages_debian = "qubes-core-agent-networking qubes-core-agent-network-manager network-manager-applet iputils-ping procps";
    } elsif ($tests =~ m/audio/) {
        $packages = "pipewire-qubes qubes-audio-daemon";
    }

    return unless ($packages || $packages_debian || $packages_fedora);

    $self->select_gui_console;
    x11_start_program('xterm');

    my $templates = script_output('qvm-ls --raw-data --fields name,klass');

    foreach (split /\n/, $templates) {
        next unless /Template/;
        s/\|.*//;
        next unless /minimal/;
        my $template = $_;

        if ($template =~ m/fedora/) {
            my $packages_cur = $packages . $packages_fedora;
            assert_script_run("qvm-run -pu root $template 'dnf install -y $packages_cur'", timeout => 300);
            if ($packages_cur =~ /kernel/) {
                assert_script_run("qvm-run -pu root $template 'grub2-mkconfig -o /boot/grub2/grub.cfg'");
            }
            if ($commands_fedora) {
                assert_script_run("qvm-run -pu root $template '$commands_fedora'", timeout => 300);
            }
        } elsif ($template =~ m/debian/) {
            my $packages_cur = $packages . $packages_debian;
            assert_script_run("qvm-run -pu root $template 'apt update && apt-get -y install $packages_cur'", timeout => 300);
            if ($packages_cur =~ /kernel/) {
                assert_script_run("qvm-run -pu root $template 'mkdir -p /boot/grub && update-grub2'");
            }
            if ($commands_debian) {
                assert_script_run("qvm-run -pu root $template '$commands_debian'", timeout => 300);
            }
        } else {
            die "Template $template not supported by this module";
        }
        if ($commands) {
            assert_script_run("qvm-run -pu root $template '$commands'", timeout => 300);
        }
        assert_script_run("qvm-shutdown --wait $template");
    }

    type_string("exit\n");
}

1;

# vim: set sw=4 et:
