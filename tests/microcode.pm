# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

# test if microcode update was applied

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm', match_typed => 'desktop-runner-xterm');
    send_key('alt-f10');
    my $cpuinfo = script_output('cat /proc/cpuinfo');
    my $family = ($cpuinfo =~ m/^cpu family[ \t]*: (\d+)/m)[0];
    my $model = ($cpuinfo =~ m/^model[ \t]*: (\d+)/m)[0];
    my $stepping = ($cpuinfo =~ m/^stepping[ \t]*: (\d+)/m)[0];
    my $ucode_version = ($cpuinfo =~ m/^microcode[ \t]*: (0x[0-9a-f]*)/m)[0];
    record_info("Running: $ucode_version");
    my $ucode_fname = sprintf("/lib/firmware/intel-ucode/%02x-%02x-%02x", $family, $model, $stepping);
    # https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files#notes
    my $version_latest = script_output("(od -t x4 $ucode_fname || :) | head -1 |cut -f 3 -d ' '");
    record_info("Latest: $version_latest");
    die "Microcode not updated: running $ucode_version expected $version_latest"
        if $version_latest and hex($ucode_version) != hex($version_latest);
    type_string("exit\n");
    assert_screen "desktop";
}

1;

# vim: set sw=4 et:
