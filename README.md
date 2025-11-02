# puff
anti compression archiving tool. The antithesis to zip and the likes


## Structure
A puff archive is a file containing a series of files and directories.
To identify a puff archive a magic sequence of bytes is used. The bee movie script.

Following the identifier bytes is a table of contents.
This enables listing information about files contained in the archive without having to read the entire archive.

The table of contents is a series of entries.
Each entry is the filename, together with an offset and length.

After the table of contents the puff algorithm used is specified. This is used to determine how to decompress the archive (or compress, given that in archive form its larger).

The header section is ended with a final special byte sequence.

After the header the file data is just appended on after another


## Processing workflow

The files specified are collected. 
A temporary file is created where data can be streamed into to not overburden the system memory.
To not overcomplicate things, all files are processed sequentially.
For each file the contents are read into memory and transformed according to the chosen algorithm.
The transformed data is written to the temporary file. And information about the offsets of that data is stored in memory in the table of contents.
After all files have been processed the actual archive is created.
Firstly the header is written to the archive.
Following that the table of contents can be written. 
After that its only a matter of picking and copying the appropriate data from the temporary file to the archive.