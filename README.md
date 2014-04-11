# app-basis-data

Method to store/manipulate simple data items in multiple backends yet access them in the same way. This is meant to be more than a key value store but less than a DB. There is no way to 'join' data items together to create more complex data items or any way to perform complex queries. Where possible data updates will be atomic, but this may not always be possible.


The initial intention is not have complex rules to match data so no or/and on searches, should throw an error if the search has more than one match

will not support cursors/iterators/paging into data, you can do that yourself once the data has been found and using a cache

This system will not be and is not expected to be fast, its purpose is to allow flexibility in datastore choice, develop on a filebased local system, and move to which ever storage system is available within your environment when you want to go live

* For DBI implementations then tables will be created as needed, DBIx::Class will be used
to keep things simple, though this has its own performance overheads

* if its redis://server:port then we will connect to that
  https://metacpan.org/pod/Redis

* if its mongo:/server:port;database=dddd;collection=cccc
  https://metacpan.org/pod/MongoDBx::Class

Initial suggested stores

* directory + msgpack or sereal files
* DBI
* mongodb
* redis

## Methods

### add

add new data, will have a uniq ID created, will be timestamped
can have unstructured data

### delete, only with uniq ID

### tagsearch

search for entries matching a single tag

tagname
match 'regexp', '='. 'like', '>=' etc
optional from/to timestamp
optional count

### wildsearch

search all entries to match some data

match 'regexp', '='. 'like', '>=' etc
optional from/to timestamp
optional count

### tagcount, wildcount

Matches the tagsearch and wildsearch, but just returns the number of matching items
not the items themselves

### data

get data for a single uniq ID

### update

update an entry (will add if no uniq ID)

### search

