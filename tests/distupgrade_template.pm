# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2025 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    wait_still_screen;
    x11_start_program('xterm');
    curl_via_netvm;

    my @templates = split / /, get_var("DISTUPGRADE_TEMPLATES");
    my @upgraded_templates = ();

    foreach (@templates) {
        die "Invalid DISTUPGRADE_TEMPLATES format" unless (m/(.*):(.*)/);
        my ($template_old, $template_new) = ($1, $2);
        assert_script_run("qvm-clone $template_old $template_new", timeout => 300);
        if ($template_new =~ m/fedora-(\d+)/) {
            my $releasever = $1;
            assert_script_run("(set -o pipefail; qvm-run -pu root $template_new dnf -y --releasever=$releasever --enablerepo=rpmfusion-free,rpmfusion-nonfree distro-sync 2>&1 | tee -a dist-upgrade.log)", timeout => 3600);
            $self->maybe_unlock_screen;
            assert_script_run("qvm-shutdown --wait $template_new", timeout => 60);
        } else {
            die "TODO";
        }
        upload_logs("/var/log/xen/console/guest-$template_new.log", failok =>1);
        push @upgraded_templates, $template_new;
    }
    upload_logs("/home/user/dist-upgrade.log", failok =>1);

    if (split(/ /, get_var("TEST_TEMPLATES")) ~~ @upgraded_templates) {
        $self->upload_packages_versions(templates => \@upgraded_templates);
    } else {
        $self->upload_packages_versions;
    }

    type_string("exit\n");
}


sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
    upload_logs("/home/user/dist-upgrade.log", failok =>1);
};

1;

# vim: set sw=4 et:
