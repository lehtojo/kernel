#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <linux/fb.h>

int main(int argument_count, const char** arguments) {
	if (argument_count < 2) {
		// If the user did not provide an image to display, print an error message and exit
		printf("Usage: display <image>\n");
		return 1;
	}

	// Load the first user argument that is the image to display
	const char* image_path = arguments[1];

	// Load the image file into memory
	int fd = open(image_path, O_RDONLY);

	if (fd < 0) {
		// If the file could not be opened, print an error message and exit
		printf("Could not open file: %s\n", image_path);
		return 1;
	}

	// Determine the size of this file
	struct stat file_info;
	fstat(fd, &file_info);

	// Allocate a buffer to hold the image
	unsigned char* image_data = malloc(file_info.st_size);

	// Read the image into memory
	read(fd, image_data, file_info.st_size);

	// Close the file
	close(fd);

	// Extract the image width, height and pixels (.bmp file)
	unsigned int width = ((int*)(image_data + 18))[0];
	unsigned int height = ((int*)(image_data + 22))[0];

	printf("Image width: %d\n", width);
	printf("Image height: %d\n", height);
	printf("Image bits per pixel: %d\n", ((int*)(image_data + 28))[0]);

	// Ensure bits per pixel is 24
	if (((int*)(image_data + 28))[0] != 24) {
		printf("Image must be 24 bits per pixel\n");
		return 1;
	}

	// Extract the image pixels
	unsigned char* pixel = image_data + ((int*)(image_data + 10))[0];
	unsigned int* pixels = malloc(width * height * sizeof(int));

	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			//pixels[x + y * width] = (int)(pixel[0]) << 8 | (int)(pixel[1]) << 16 | (int)(pixel[2]) << 24 | 0xff;
			pixels[x + y * width] = (int)(pixel[1]) << 0 | (int)(pixel[2]) << 8 | (int)(pixel[0]) << 16 | 0xff000000;
			pixel += 3;
		}

		pixel = (unsigned long long)(pixel + 3) & ~3; // Align to next 4 bytes
	}

	// Display the image on the screen
	int framebuffer_fd = open("/dev/fb0", O_RDWR);

	if (framebuffer_fd < 0) {
		printf("Failed to open the framebuffer device\n");
		return 1;
	}

	// Load information about the framebuffer before displaying
	struct fb_fix_screeninfo framebuffer_info;

	if (ioctl(framebuffer_fd, FBIOGET_FSCREENINFO, &framebuffer_info) != 0) {
		printf("Failed to retrieve framebuffer info\n");
		return 1;
	}

	// Load display information and enable the framebuffer
	struct fb_var_screeninfo display_info;

	if (ioctl(framebuffer_fd, FBIOGET_VSCREENINFO, &display_info) != 0) {
		printf("Failed to retrieve display info\n");
		return 1;
	}

	// Verify the image fits
	if (width > display_info.xres || height > display_info.yres) {
		printf("Image is too large to display\n");
		return 1;
	}

	off_t framebuffer_offset = framebuffer_info.smem_start;
	size_t framebuffer_size = framebuffer_info.smem_len;

	char* framebuffer = mmap(NULL, framebuffer_size, PROT_READ | PROT_WRITE, MAP_SHARED, framebuffer_fd, 0);

	if (framebuffer == MAP_FAILED) {
		printf("Failed to map the framebuffer\n");
		return 1;
	}

	printf("line_length=%d, xres=%d, yres=%d, vxres=%d, vyres=%d, xoffset=%d, yoffset=%d, bpp=%d\n",
		framebuffer_info.line_length, display_info.xres, display_info.yres, display_info.xres_virtual,
		display_info.yres_virtual, display_info.xoffset, display_info.yoffset, display_info.bits_per_pixel
	);

	printf("red: offset=%d, length=%d\n", display_info.red.offset, display_info.red.length);
	printf("green: offset=%d, length=%d\n", display_info.green.offset, display_info.green.length);
	printf("blue: offset=%d, length=%d\n", display_info.blue.offset, display_info.blue.length);

	int activated = 0;

	while (1) {
		memset(framebuffer + framebuffer_offset, 0, framebuffer_size);

		// Copy the image into the framebuffer
		for (unsigned int y = 0; y < height; y++) {
			for (unsigned int x = 0; x < width; x++) {
				// Extract the pixel
				unsigned int pixel = pixels[(height - 1 - y) * width + x];
	
				// Calculate the offset of this pixel in the framebuffer
				off_t framebuffer_pixel_offset = framebuffer_offset + x * sizeof(int) + y * framebuffer_info.line_length;

				// Copy the pixel into the framebuffer
				memcpy(framebuffer + framebuffer_pixel_offset, &pixel, 4);
			}
		}

		// Enable the framebuffer
		display_info.activate |= FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE;

		// Update the display info
		if (activated == 0 && ioctl(framebuffer_fd, FBIOPUT_VSCREENINFO, &display_info) != 0) {
			printf("Failed to update display info\n");
			return 1;
		}

		activated = 1;

		while (1) {}
	}

	munmap(framebuffer, framebuffer_size);
	close(framebuffer_fd);
	return 0;
}