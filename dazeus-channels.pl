#!/usr/bin/perl
# Channel plugin for DaZeus
# Copyright (C) 2007  Sjors Gielen
# Copyright (C) 2014  Aaron van Geffen
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use DaZeus;
use warnings;
use strict;

my ($socket) = @ARGV;
if(!$socket) {
	die "Usage: $0 socket\n";
}

my $dazeus = DaZeus->connect($socket) or die $!;

$dazeus->subscribe_command("join" => \&cmd_join);
$dazeus->subscribe_command("part" => \&cmd_part);
$dazeus->subscribe_command("leave" => \&cmd_part);
$dazeus->subscribe_command("cycle" => \&cmd_cycle);
$dazeus->subscribe_command("autojoin" => \&cmd_autojoin);
$dazeus->subscribe_command("identify" => \&cmd_identify);

$dazeus->subscribe("connect" => sub {
	my ($dazeus, $event) = @_;
	my $network = $event->{'params'}[0];
	on_connect($dazeus, $network);
});

# simulate a re-connection to all networks
my $networks = $dazeus->networks();
foreach(@$networks) {
	on_connect($dazeus, $_);
}

while($dazeus->handleEvents()) {}

sub reply {
	my ($response, $network, $sender, $channel) = @_;

	if ($channel eq $dazeus->getNick($network)) {
		$dazeus->message($network, $sender, $response);
	} else {
		$dazeus->message($network, $channel, $response);
	}
}

sub cmd_join {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	$args = $args ? $args : $channel;
	$dazeus->join($network, $args);
	reply("OK, joined $args.", $network, $sender, $channel);
}

sub cmd_part {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	$args = $args ? $args : $channel;
	$dazeus->part($network, $args);
	reply("OK, left $args.", $network, $sender, $channel);
}

sub cmd_cycle {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	$args = $args ? $args : $channel;
	$dazeus->part($network, $args); 
	$dazeus->join($network, $args); 
	reply("OK, cycled $args.", $network, $sender, $channel);
}

sub get_autojoin {
	my ($dazeus, $network) = @_;
	my $a = $dazeus->getProperty("perl.DazChannel.autojoin", $network);
	return $a ? @$a : ();
}

sub set_autojoin {
	my ($dazeus, $network, $autojoin) = @_;
	$dazeus->setProperty("perl.DazChannel.autojoin", $autojoin, $network);
}

sub uniq {
	my (@set) = @_;
	my %set;
	foreach(@set) {
		$set{$_} = 1;
	}
	return keys %set;
}

sub remove {
	my ($list, @vars) = @_;
	my %list;
	foreach(@$list) {
		$list{$_} = 1;
	}
	foreach(@vars) {
		delete $list{$_};
	}
	return keys %list;
}

sub autojoin_now {
	my ($dazeus, $network) = @_;
	my @current_channels = get_autojoin($dazeus, $network);
	foreach(@current_channels) {
		$dazeus->join($network, $_);
	}
}

sub cmd_autojoin {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	my ($verb, @rest) = split /\s+/, $args;
	my $rest = join " ", @rest;

	$rest = $rest ? $rest : $channel;

	if($verb eq "add") {
		my @current_channels = get_autojoin($dazeus, $network);
		my @channels = split /\s+/, $rest;
		my @new_channels = uniq(@current_channels, @channels);
		set_autojoin($dazeus, $network, \@new_channels);
		reply("Done.", $network, $sender, $channel);
	} elsif($verb eq "rm" || $verb eq "del") {
		my @current_channels = get_autojoin($dazeus, $network);
		my @channels = split /\s+/, $rest;
		my @new_channels = remove(\@current_channels, @channels);
		set_autojoin($dazeus, $network, \@new_channels);
		reply("Done.", $network, $sender, $channel);
	} elsif($verb eq "get") {
		my @current_channels = get_autojoin($dazeus, $network);
		my $channels = join ", ", @current_channels;
		reply("Autojoin channels on $network: $channels", $network, $sender, $channel);
	} elsif($verb eq "now") {
		autojoin_now($dazeus, $network);
		reply("Done.", $network, $sender, $channel);
	} else {
		reply("Usage: autojoin <add|rm|del|get|now> [...]");
	}
}

use constant nickservpass_var => "perl.DazLoader.nickservpass";
use constant nickservnick_var => "perl.DazLoader.nickservnick";

sub identify_now {
	my ($dazeus, $network) = @_;
	my $pass = $dazeus->getProperty(nickservpass_var, $network);
	my $nick = $dazeus->getProperty(nickservnick_var, $network) || "NickServ";
	$dazeus->message($network, $nick, "IDENTIFY " . $pass);
}

sub cmd_identify {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	my ($verb, @rest) = split /\s+/, $args;
	my $rest = join " ", @rest;

	if($verb eq "password") {
		$dazeus->setProperty(nickservpass_var, $rest, $network);
		reply("Done.", $network, $sender, $channel);
	} elsif($verb eq "to") {
		$dazeus->setProperty(nickservnick_var, $rest, $network);
		reply("Done.", $network, $sender, $channel);
	} elsif($verb eq "now") {
		identify_now($dazeus, $network);
		reply("Done.", $network, $sender, $channel);
	}
}

sub on_connect {
	my ($dazeus, $network) = @_;
	identify_now($dazeus, $network);
	autojoin_now($dazeus, $network);
}

1;
