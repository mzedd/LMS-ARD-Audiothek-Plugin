package Plugins::ARDAudiothek::ProtocolHandler;

# ARD Audiothek Plugin for the Logitech Media Server (LMS)
# Copyright (C) 2021  Max Zimmermann  software@maxzimmermann.xyz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Protocolhandler for ardaudiothek:// URLS

use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::API;

use constant PLAYLIST_EPISODE_LIMIT => 1000;

my $log = logger('plugin.ardaudiothek');

sub scanUrl {
    my ($class, $uri, $args) = @_;
    my $id = _itemIdFromUri($uri);

    Plugins::ARDAudiothek::API->getEpisode(
        sub {
            my $episode = shift;
            unless($episode && $episode->{url}) {
                $args->{cb}->(undef, 'SCANNER_REMOTE_NO_URL_PROVIDED', @{$args->{pt} || []})
                    if $args->{cb};
                return;
            }
            my $url = $episode->{url};
            my $isLivestream = $id =~ /^urn:ard:(?:permanent|event)-livestream:/;

            if($isLivestream && (my $song = $args->{song})) {
                # Keep station fallback separate from LMS's changing stream data.
                $song->pluginData(ardaudiothekLivestream => {
                    uri => $uri, url => $url, episode => $episode
                });
            }

            my $scanArgs = $args;
            if(my $song = $args->{song}) {
                $scanArgs = {%{$args}, cb => sub {
                    my ($track, $error, @context) = @_;
                    if($track && !Slim::Music::Info::isPlaylist($track, $track->content_type)) {
                        # Keep the plugin URI as the playlist/source identity.
                        # The resolved track supplies the audio and format data.
                        $song->_currentTrack($track);
                        $song->streamUrl($track->url);
                        $track = $song->track;
                    }
                    $args->{cb}->($track, $error, @context) if $args->{cb};
                }};
            }
            Slim::Utils::Scanner::Remote->scanURL($url, $scanArgs);
            return if $isLivestream;

            my $client = $args->{client}->master;
            my $image = Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl});

            $client->playingSong->pluginData(wmaMeta => {
                icon   => $image,
                cover  => $image,
                artist => $episode->{show},
                title  => $episode->{title}
            });

            Slim::Control::Request::notifyFromArray($client, [ 'newmetadata' ]);
        },
        {
            id => $id
        }
    );

    return;
}

sub explodePlaylist {
    my ($class, $client, $uri, $callback) = @_;

    my $adapter = sub {
        my $playlist = shift;
        my $items = Plugins::ARDAudiothek::Plugin::episodesToOPML($playlist->{episodes});
        $callback->({items => $items});
    };

    my $variables = {
        id => _itemIdFromUri($uri),
        offset => 0,
        limit => PLAYLIST_EPISODE_LIMIT
    };

    if($uri =~ /ardaudiothek:\/\/urn:ard:(?:episode|(?:permanent|event)-livestream):[a-z0-9]+/) {
        $callback->([$uri]);
    }
    elsif($uri =~ /ardaudiothek:\/\/urn:ard:show:[a-z0-9]+/) {
        Plugins::ARDAudiothek::API->getProgramSet($adapter, $variables);
    }
    elsif($uri =~ /ardaudiothek:\/\/urn:ard:collection:[a-z0-9]+/) {
        Plugins::ARDAudiothek::API->getEditorialCollection($adapter, $variables);
    }
    else {
        $callback->([]);
    }
}

sub getMetadataFor {
    my ($class, $client, $uri) = @_;

    if($client && $client->can('playingSong') && (my $song = $client->playingSong())) {
        if(my $stream = $song->pluginData('ardaudiothekLivestream')) {
            my $track = $song->track;
            my $currentTrack = $song->currentTrack || $track;
            my $trackUrl = $track ? $track->url : '';
            my $currentUrl = $currentTrack ? $currentTrack->url : '';
            if($uri eq $stream->{uri} || $uri eq $stream->{url}
                || $uri eq $trackUrl || $uri eq $currentUrl) {
                # LMS stores ICY titles and covers under the playlist URL,
                # which remains the plugin URI after resolving the audio.
                return $class->_livestreamMetadata($client, $trackUrl || $currentUrl, $stream);
            }
        }
    }

    # Skip URIs that do not match the current ARD format.
    if($uri !~ m/ardaudiothek:\/\/urn:ard:(episode|show|collection|(?:permanent|event)-livestream):[a-z0-9]+/) {
        return;
    }

    my $episode;
    my $waitingForResponse = 1;

    Plugins::ARDAudiothek::API->getEpisode(
        sub {
            $episode = shift;

            # A cache miss is resolved asynchronously. Ask LMS to fetch the
            # metadata again once the episode data has arrived.
            if(!$waitingForResponse && defined $client && defined $episode) {
                Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
            }
        },
        { id => _itemIdFromUri($uri) }
    );

    $waitingForResponse = 0;

    if(not defined $episode) {
        return {u => $uri}; # identify the source while metadata loads
    }

    my $image = Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl});

    return {
        # LMS status uses this URL to identify the plugin in Material Skin.
        u => $uri,
        icon => $image,
        cover => $image,
        title => $episode->{title},
        artist => $episode->{show},
        duration => $episode->{duration},
        description => $episode->{description}
    };
}

sub _livestreamMetadata {
    my ($class, $client, $url, $stream) = @_;
    my $episode = $stream->{episode};
    my $image = Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl});
    my $metadata = {
        u => $stream->{uri},
        title => $episode->{title}, artist => $episode->{show},
        album => $episode->{title},
        icon => $image, cover => $image, description => $episode->{description}
    };
    return $metadata unless defined $url && length $url;

    # Preserve the plugin invocant for HTTP's handler recursion guard.
    # LMS already handles stream updates, notifications and buffering delay.
    my $live = $class->SUPER::getMetadataFor($client, $url) || {};
    for my $field (qw(artist title album cover)) {
        next unless defined $live->{$field} && length $live->{$field};
        next if $field eq 'title' && $live->{$field} eq $url;
        next if $field eq 'cover' && $live->{$field} =~ m{^/?html/images/radio\.png$};
        $metadata->{$field} = $live->{$field};
    }
    # Keep the station name only once when it also occupies the artist field.
    if($metadata->{album} && lc($metadata->{album}) eq lc($episode->{title} || '')
        && lc($metadata->{artist} || '') eq lc($metadata->{album})) {
        $metadata->{artist} = '';
    }
    $metadata->{icon} = $metadata->{cover};
    return $metadata;
}

sub _itemIdFromUri {
    my $uri = shift;

    my $id = $uri;
    $id =~ s/ardaudiothek:\/\///g;

    return $id;
}

1;
