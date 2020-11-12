#include "font_manager.h"
#include "truetype.h"

#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include <stb/stb_truetype.h>

/*
	F->priority is a circular linked list for the LRU cache.
	F->hash is for lookup with [font, codepoint].
*/

#define COLLISION_STEP 7
#define DISTANCE_OFFSET 5
#define ORIGINAL_SIZE (FONT_MANAGER_GLYPHSIZE - DISTANCE_OFFSET * 2)

static const int SAPCE_CODEPOINT[] = {
    ' ', '\t', '\n', '\r',
};

static inline int
is_space_codepoint(int codepoint){
    for (int ii=0; ii < sizeof(SAPCE_CODEPOINT)/sizeof(SAPCE_CODEPOINT[0]); ++ii){
        if (codepoint == SAPCE_CODEPOINT[ii]){
            return 1;
        }
    }
    return 0;
}

static inline const stbtt_fontinfo*
get_ttf(struct font_manager *F, int fontid){
	#ifdef TEST_CASE
	return (&F->ttf->fontinfo[fontid - 1]);
	#else //!TEST_CASE
	return truetype_font(F->ttf, fontid, F->L);
	#endif //TEST_CASE
}

static inline int
ttf_with_family(struct font_manager *F, const char* family){
	#ifdef TEST_CASE
	assert(0);
	return -1;	// NOT SUPPORT
	#else
	return truetype_name(F->L, family);
	#endif //TEST_CASE
}

void
font_manager_init(struct font_manager *F, struct truetype_font *ttf, void *L) {
	F->version = 1;
	F->count = 0;
	F->ttf = ttf;
	F->L = L;
	F->dpi_perinch = 0;
	font_manager_sdf_onedge_value(F, 180);
// init priority list
	int i;
	for (i=0;i<FONT_MANAGER_SLOTS;i++) {
		F->priority[i].prev = i+1;
		F->priority[i].next = i-1;
	}
	int lastslot = FONT_MANAGER_SLOTS-1;
	F->priority[0].next = lastslot;
	F->priority[lastslot].prev = 0;
	F->list_head = lastslot;
// init hash
	for (i=0;i<FONT_MANAGER_SLOTS;i++) {
		F->slots[i].codepoint_ttf = -1;
	}
	for (i=0;i<FONT_MANAGER_HASHSLOTS;i++) {
		F->hash[i] = -1;	// empty slot
	}
}

static inline int
codepoint_ttf(int font, int codepoint) {
	return (font << 24 | codepoint);
}

static inline int
hash(int value) {
	return (value * 0xdeece66d + 0xb) % FONT_MANAGER_HASHSLOTS;
}

static int
hash_lookup(struct font_manager *F, int cp) {
	int slot;
	int position = hash(cp);
	while ((slot = F->hash[position]) >= 0) {
		struct font_slot * s = &F->slots[slot];
		if (s->codepoint_ttf == cp)
			return slot;
		position = (position + COLLISION_STEP) % FONT_MANAGER_HASHSLOTS;
	}
	return -1;
}

static void rehash(struct font_manager *F);

static void
hash_insert(struct font_manager *F, int cp, int slotid) {
	++F->count;
	if (F->count > FONT_MANAGER_SLOTS + FONT_MANAGER_SLOTS/2) {
		rehash(F);
	}
	int position = hash(cp);
	int slot;
	while ((slot = F->hash[position]) >= 0) {
		struct font_slot * s = &F->slots[slot];
		if (s->codepoint_ttf < 0)
			break;
		assert(s->codepoint_ttf != cp);

		position = (position + COLLISION_STEP) % FONT_MANAGER_HASHSLOTS;
	}
	F->hash[position] = slotid;
	F->slots[slotid].codepoint_ttf = cp;
}

static void
rehash(struct font_manager *F) {
	int i;
	for (i=0;i<FONT_MANAGER_HASHSLOTS;i++) {
		F->hash[i] = -1;	// reset slots
	}
	F->count = 0;
	int count = 0;
	for (i=0;i<FONT_MANAGER_SLOTS;i++) {
		int cp = F->slots[i].codepoint_ttf;
		if (cp >= 0) {
			assert(++count <= FONT_MANAGER_SLOTS);
			hash_insert(F, cp, i);
		}
	}
}

static void
remove_node(struct font_manager *F, struct priority_list *node) {
	struct priority_list *prev_node = &F->priority[node->prev];
	struct priority_list *next_node = &F->priority[node->next];
	prev_node->next = node->next;
	next_node->prev = node->prev;
}

static void
touch_slot(struct font_manager *F, int slotid) {
	struct priority_list *node = &F->priority[slotid];
	node->version = F->version;
	if (slotid == F->list_head)
		return;
	remove_node(F, node);
	// insert before head
	int head = F->list_head;
	int tail = F->priority[head].prev;
	node->prev = tail;
	node->next = head;
	struct priority_list *head_node = &F->priority[head];
	struct priority_list *tail_node = &F->priority[tail];
	head_node->prev = slotid;
	tail_node->next = slotid;
	F->list_head = slotid;
}

// 1 exist in cache. 0 not exist in cache , call font_manager_update. -1 failed.
int
font_manager_touch(struct font_manager *F, int font, int codepoint, struct font_glyph *glyph) {
	int cp = codepoint_ttf(font, codepoint);
	int slot = hash_lookup(F, cp);
	if (slot >= 0) {
		touch_slot(F, slot);
		struct font_slot *s = &F->slots[slot];
		glyph->offset_x = s->offset_x;
		glyph->offset_y = s->offset_y;
		glyph->advance_x = s->advance_x;
		glyph->advance_y = s->advance_y;
		glyph->w = s->w;
		glyph->h = s->h;
		glyph->u = (slot % FONT_MANAGER_SLOTLINE) * FONT_MANAGER_GLYPHSIZE;
		glyph->v = (slot / FONT_MANAGER_SLOTLINE) * FONT_MANAGER_GLYPHSIZE;

		return 1;
	}
	int last_slot = F->priority[F->list_head].prev;
	struct priority_list *last_node = &F->priority[last_slot];
	if (font <= 0) {
		// invalid font
		memset(glyph, 0, sizeof(*glyph));
		return -1;
	}

	const struct stbtt_fontinfo *fi = get_ttf(F, font);

	float scale = stbtt_ScaleForPixelHeight(fi, ORIGINAL_SIZE);
	int ascent, descent, lineGap;
	int advance, lsb;
	int ix0, iy0, ix1, iy1;

	stbtt_GetFontVMetrics(fi, &ascent, &descent, &lineGap);
	stbtt_GetCodepointHMetrics(fi, codepoint, &advance, &lsb);
	stbtt_GetCodepointBitmapBox(fi, codepoint, scale, scale, &ix0, &iy0, &ix1, &iy1);

	glyph->w = ix1-ix0 + DISTANCE_OFFSET * 2;
	glyph->h = iy1-iy0 + DISTANCE_OFFSET * 2;
	glyph->offset_x = (short)(lsb * scale) - DISTANCE_OFFSET;
	glyph->offset_y = iy0 - DISTANCE_OFFSET;
	glyph->advance_x = (short)(((float)advance) * scale + 0.5f);
	glyph->advance_y = (short)((ascent + descent + lineGap) * scale + 0.5f);
	glyph->u = 0;
	glyph->v = 0;

	if (last_node->version == F->version)	// full ?
		return -1;

	return 0;
}

static inline int
scale_font(int v, float scale, int size) {
	return ((int)(v * scale * size) + ORIGINAL_SIZE/2) / ORIGINAL_SIZE;
}

void
font_manager_fontheight(struct font_manager *F, int fontid, int size, int *ascent, int *descent, int *lineGap) {
	if (fontid <= 0) {
		*ascent = 0;
		*descent = 0;
		*lineGap = 0;
	}

	const struct stbtt_fontinfo *fi = get_ttf(F, fontid);
	float scale = stbtt_ScaleForPixelHeight(fi, ORIGINAL_SIZE);
	stbtt_GetFontVMetrics(fi, ascent, descent, lineGap);
	*ascent = scale_font(*ascent, scale, size);
	*descent = scale_font(*descent, scale, size);
	*lineGap = scale_font(*lineGap, scale, size);
}

void
font_manager_boundingbox(struct font_manager *F, int fontid, int size, int *x0, int *y0, int *x1,int *y1){
	const struct stbtt_fontinfo *fi = get_ttf(F, fontid);
	stbtt_GetFontBoundingBox(fi, x0, y0, x1, y1);
	float scale = stbtt_ScaleForPixelHeight(fi, ORIGINAL_SIZE);
	*x0 = scale_font(*x0, scale, size);
	*y0 = scale_font(*y0, scale, size);
	*x1 = scale_font(*x1, scale, size);
	*y1 = scale_font(*y1, scale, size);
}

int
font_manager_pixelsize(struct font_manager *F, int fontid, int pointsize){
	//TODO: need set dpi when init font_manager
	const int defaultdpi = 96;
	const int dpi = F->dpi_perinch == 0 ? defaultdpi : F->dpi_perinch;
	return (int)((pointsize / 72.f) * dpi + 0.5f);
}

int
font_manager_glyph(struct font_manager *F, int fontid, int codepoint, int size, struct font_glyph *g, struct font_glyph *og){
    int updated = font_manager_touch(F, fontid, codepoint, g);

    if (og){
        if (is_space_codepoint(codepoint)){
			updated = 1;	// not need update
			*og = *g;
            og->w = og->h = 0;
        } else {
            *og = *g;
        }
    }

    font_manager_scale(F, g, size);
    return updated;
}

const char *
font_manager_update(struct font_manager *F, int fontid, int codepoint, struct font_glyph *glyph, uint8_t *buffer) {
	if (fontid <= 0)
		return "Invalid font";
	int cp = codepoint_ttf(fontid, codepoint);
	int slot = hash_lookup(F, cp);
	if (slot < 0) {
		// move last node to head
		slot = F->priority[F->list_head].prev;
		struct priority_list *last_node = &F->priority[slot];
		if (last_node->version == F->version) {	// full ?
			return "Too many glyph";
		}
		last_node->version = F->version;
		F->list_head = slot;
		F->slots[slot].codepoint_ttf = -1;
		hash_insert(F, cp, slot);
	}

	const struct stbtt_fontinfo *fi = get_ttf(F, fontid);
	float scale = stbtt_ScaleForPixelHeight(fi, ORIGINAL_SIZE);

	int width, height, xoff, yoff;

	unsigned char *tmp = stbtt_GetCodepointSDF(fi, scale, codepoint, DISTANCE_OFFSET, F->sdf.onedge_value, F->sdf.pixel_dist_scale, &width, &height, &xoff, &yoff);
	if (tmp == NULL){
		return NULL;
	}
	int size = width * height;
	int gsize = glyph->w * glyph->h; 
	if (size > gsize) {
		size = gsize;
	}
	memcpy(buffer, tmp, size);

	stbtt_FreeSDF(tmp, fi->userdata);

	struct font_slot *s = &F->slots[slot];
	s->codepoint_ttf = cp;
	s->offset_x = glyph->offset_x;
	s->offset_y = glyph->offset_y;
	s->advance_x = glyph->advance_x;
	s->advance_y = glyph->advance_y;
	s->w = glyph->w;
	s->h = glyph->h;

	glyph->u = (slot % FONT_MANAGER_SLOTLINE) * FONT_MANAGER_GLYPHSIZE;
	glyph->v = (slot / FONT_MANAGER_SLOTLINE) * FONT_MANAGER_GLYPHSIZE;

	return NULL;
}

void
font_manager_flush(struct font_manager *F) {
	++F->version;
}

int
font_manager_addfont_with_family(struct font_manager *F, const char* family) {
	return ttf_with_family(F, family);
}

static inline void
scale(short *v, int size) {
	*v = (*v * size + ORIGINAL_SIZE/2) / ORIGINAL_SIZE;
}

static inline void
uscale(uint16_t *v, int size) {
	*v = (*v * size + ORIGINAL_SIZE/2) / ORIGINAL_SIZE;
}

void
font_manager_scale(struct font_manager *F, struct font_glyph *glyph, int size) {
	(void)F;
	scale(&glyph->offset_x, size);
	scale(&glyph->offset_y, size);
	scale(&glyph->advance_x, size);
	scale(&glyph->advance_y, size);
	uscale(&glyph->w, size);
	uscale(&glyph->h, size);
}

float
font_manager_sdf_mask(struct font_manager *F, int offset){
	return (F->sdf.onedge_value + offset) / 255.0f;
}

float
font_manager_sdf_distance(struct font_manager *F, float numpixel){
	return (numpixel * F->sdf.pixel_dist_scale) / 255.f;
}

void
font_manager_sdf_onedge_value(struct font_manager *F, int onedge_value){
	F->sdf.onedge_value = onedge_value;
	F->sdf.pixel_dist_scale = F->sdf.onedge_value / ((float)DISTANCE_OFFSET);
}

#ifdef TEST_CASE
#include <stdlib.h>
#include <stdio.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb/stb_image_write.h>
static void
add_font(void *ttfbuffer, struct truetype_font *ttf, int fontid){
	stbtt_InitFont(&ttf->fontinfo[fontid - 1], ttfbuffer, stbtt_GetFontOffsetForIndex(ttfbuffer, 0));
}

int
main() {
	FILE* f = NULL;
	fopen_s(&f, "simsun.ttc", "rb");
	fseek(f, 0, SEEK_END);
	int sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	void * ttfbuffer = malloc(sz);
	int read = (int)fread(ttfbuffer, 1, sz, f);
	fprintf(stderr, "read %d %d\n", sz, read);
	fclose(f);

	struct truetype_font ttf;

	const int fontid = 1;
	add_font(ttfbuffer, &ttf, fontid);
	struct font_manager F;
	font_manager_init(&F, &ttf, NULL);

	fprintf(stderr,"load font %d\n", fontid);

	int bufsize = FONT_MANAGER_GLYPHSIZE * FONT_MANAGER_GLYPHSIZE * 5;
	uint8_t* buffer = malloc(bufsize);
	memset(buffer, 0, bufsize);

	uint8_t *p = buffer;
	const char* s = "ABC";
	int x = 0, y = 0;
	for (const char* ss=s; *ss; ++ss){
		struct font_glyph g;
		int codepoint = *ss;	//0x6C49
		font_manager_touch(&F, fontid, codepoint, &g);

		uint8_t *p = malloc(g.w * g.h);
		const char * err = font_manager_update(&F, fontid, codepoint, &g, p);
		if (err != NULL) {
			fprintf(stderr, "Error : %s\n", err);
		} else {
			fprintf(stderr, "x=%d y=%d (%d x %d) (%d x %d), u=%d v=%d\n",
				g.offset_x, g.offset_y,
				g.advance_x, g.advance_y,
				g.w, g.h,
				g.u, g.v);
			
			uint8_t *pp = buffer + x;
			const uint8_t* p1 = p;
			for (int ii=0; ii<g.h; ++ii){
				memcpy(pp, p1, g.w);
				pp += FONT_MANAGER_GLYPHSIZE * 5;
				p1 += g.w;
			}

			x += g.w;
		}
	}
	
	stbi_write_bmp("sdf.bmp", FONT_MANAGER_GLYPHSIZE * 5, FONT_MANAGER_GLYPHSIZE, 1, buffer);
	// printf("P2\n%d %d\n255\n", g.w, g.h);
	// int i,j;
	// for (i=0;i<g.h;i++) {
	// 	for (j=0;j<g.w;j++) {
	// 		printf("%d ", buffer[i*g.w+j]);
	// 	}
	// 	printf("\n");
	// }

	free(buffer);

	return 0;
}
#endif //TEST_CASE