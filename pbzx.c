/*
	Obtained from http://www.newosxbook.com/src.jl?tree=listings&file=pbzx.c
	Jonathan Levin, http://newosxbook.com/ - 03/18/14
	Modifications by Smx <smxdev4@gmail.com>
*/
#define _GNU_SOURCE
#include <stdio.h> // for printf
#include <string.h> // for strncmp
#include <fcntl.h>  // for O_RDONLY
#include <unistd.h> // everything else
#include <stdlib.h> // malloc
#include <stdint.h>

#ifdef DUMP_CHUNKS
static int dump_chunks = 1;
#else
static int dump_chunks=  0;
#endif

int main(int argc, const char *argv[]){
	char header[4];
	int fd = 0;

	if (argc < 2) {
		fd  = 0 ;
	} else {
		fd = open (argv[1], O_RDONLY);
		if (fd < 0) {
			perror (argv[1]);
			return 5;
		}
	}

	read (fd, header, 4);
	if (strncmp(header, "pbzx", 4)) {
		fprintf(stderr, "Can't find pbzx magic\n");
		return 1;
	}

	// Now, if it IS a pbzx
	uint64_t length = 0;
	uint64_t flags = 0;

	read (fd, &flags, sizeof (uint64_t));
	flags = __builtin_bswap64(flags);

	fprintf(stderr,"Flags: 0x%zx\n", flags);

	uint i = 0;
	while (flags &  0x01000000) {  // have more chunks
		i++;
		read (fd, &flags, sizeof (uint64_t));
		flags = __builtin_bswap64(flags);
		read (fd, &length, sizeof (uint64_t));
		length = __builtin_bswap64(length);

		fprintf(stderr,"Chunk #%u (flags: %zx, length: %zu bytes)\n", i, flags, length);

		// Let's ignore the fact I'm allocating based on user input, etc..
		char *buf = calloc (1, length);
		read (fd, buf, length);

		// We want the XZ header/footer if it's the payload, but prepare_payload doesn't have that,
		// so warn and skip
		if (strncmp(buf, "\xfd""7zXZ\0", 6)) {
			fprintf (stderr, "Warning: Can't find XZ header. This is likely not XZ data\n");
		// if we have the header, there had better be a footer, too
		} else if (strncmp(buf + length -2, "YZ", 2)) {
			fprintf (stderr, "Warning: Can't find XZ footer. This is probably bad.\n");
		} else {
			write (1, buf, length);
		}

		if(dump_chunks){
			char *chunk_path;
			asprintf(&chunk_path, "chunk_%u.xz", i);
			int chunk_fd = open(chunk_path, O_WRONLY | O_CREAT, (mode_t)0666);
			free(chunk_path);
			if(chunk_fd < 0){
				fprintf(stderr, "ERROR: Cannot open the chunk for writing\n");
				fprintf(stderr, "Disabling dump mode...\n");
				dump_chunks = 0;
			} else {
				write(chunk_fd, buf, length);
				close(chunk_fd);
			}
		}
		free(buf);
	}
	return 0;
}