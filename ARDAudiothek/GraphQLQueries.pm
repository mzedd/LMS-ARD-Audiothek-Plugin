package Plugins::ARDAudiothek::GraphQLQueries;

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

use strict;

use constant {
    FRAGMENT_ITEM =>
    'fragment item on Item {
      id
      title
      synopsis
      duration
      image {
        url
      }
      audios {
        url
      }
      programSet {
        title
      }
    }',

    FRAGMENT_PROGRAMSETMETA =>
    'fragment programSetMeta on ProgramSet {
      id
      title
      image {
        url
      }
    }',

    FRAGMENT_PERMANENTLIVESTREAM =>
    'fragment permanentLivestreams on PermanentLivestream {
      title
      image {
        url
      }
      audios {
        url
      }
    }'
};

use constant {
    DISCOVER =>
    '{
      homescreen {
        sections {
          nodes {
            id
            ...item
            ...programSetMeta
            ...on EditorialCollection {
              id
              image {
                url
              }
              title
            }
          }
        }
      }
    }'
    .FRAGMENT_ITEM
    .FRAGMENT_PROGRAMSETMETA,

    ORGANIZATIONS =>
    '{
      organizations {
        nodes {
          title
          image {
            url
          }
          publicationServicesByOrganizationName {
            nodes {
              title
              image {
                url
              }
              permanentLivestreams {
                totalCount
                nodes {
                  ...permanentLivestreams
                }
              }
              programSets {
                nodes {
                  ...programSetMeta
                }
              }
            }
          }
        }
      }
    }'
    .FRAGMENT_PERMANENTLIVESTREAM
    .FRAGMENT_PROGRAMSETMETA,

    EDITORIAL_CATEGORIES => 
    '{
      editorialCategories {
        nodes {
          id
          title
          image {
            url
          }
        }
      }
    }',

    EDITORIAL_CATEGORY_PLAYLISTS =>
    '{
      editorialCategory(id: $id) {
        sections {
          nodes {
            ...item
            ...programSetMeta
          }
        }
      }
    }'
    .FRAGMENT_ITEM
    .FRAGMENT_PROGRAMSETMETA,

    PROGRAM_SET => 
    '{
      programSet(id: $id) {
        id
        title
        numberOfElements
        items(offset: $offset, first: $limit, filter: {isPublished: {equalTo: true}}) {
          nodes {
            ...item
          }
        }
      }
    }'
    .FRAGMENT_ITEM, 

    EPISODE =>
    '{
      item(id: $id) {
        ...item
      }
    }'
    .FRAGMENT_ITEM
};

1;
