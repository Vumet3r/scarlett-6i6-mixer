# SPDX-License-Identifier: GPL-2.0
CC      = cc
CXX     = clang++
CFLAGS  = -Wall -Wextra -std=c23
OBJCXXFLAGS = -Wall -Wextra -std=c++20 -ObjC++
LDFLAGS = -framework IOUSBHost -framework IOKit -framework CoreFoundation
INCDIR  = -Iinclude
BUILD   = build
SRC     = src
TARGETS = scarlett-daemon scarlett-client

DAEMON_OBJS = main.o usb-io.o socket-server.o
CLIENT_OBJS = client.o

DAEMON_OBJS  := $(patsubst %,$(BUILD)/%,$(DAEMON_OBJS))
CLIENT_OBJS  := $(patsubst %,$(BUILD)/%,$(CLIENT_OBJS))

.PHONY: all clean

all: $(TARGETS)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(SRC)/%.c include/*.h | $(BUILD)
	$(CC) $(CFLAGS) $(INCDIR) -c $< -o $@

$(BUILD)/%.o: $(SRC)/%.mm include/*.h | $(BUILD)
	$(CXX) $(OBJCXXFLAGS) $(INCDIR) -c $< -o $@

scarlett-daemon: $(DAEMON_OBJS)
	$(CXX) $(INCDIR) $^ -o $(BUILD)/$@ $(LDFLAGS)

scarlett-client: $(CLIENT_OBJS)
	$(CC) $(INCDIR) $^ -o $(BUILD)/$@

clean:
	rm -rf $(BUILD)
