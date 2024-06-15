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
use mmapi;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::File qw(path);

sub run {
    my ($self) = @_;
    my $my_id = get_current_job_id();
    my $my_info = get_job_info($my_id);
    my $ua = Mojo::UserAgent->new;
    my $url = Mojo::URL->new(get_required_var("OPENQA_URL"));

    return if (!$my_info->{has_parents});
    my $parent = $my_info->{parents}->{Chained}[0] // $my_info->{parents}->{'Directly chained'}[0];
    $url->path("tests/$parent/file/sut_packages.txt");
    my $res = $ua->get($url)->res;
    return if $res->code == 404;
    die $res->error if $res->error;
    
    path("sut_packages.txt")->spew($res->body);
}

1;

# vim: set sw=4 et:
