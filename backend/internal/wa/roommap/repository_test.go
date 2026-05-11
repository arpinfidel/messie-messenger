package roommap

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func TestListRoomMappings(t *testing.T) {
	t.Helper()

	dbPath := filepath.Join(t.TempDir(), "bridge.db")
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	statements := []string{
		`CREATE TABLE portal (
			bridge_id TEXT NOT NULL,
			id TEXT NOT NULL,
			receiver TEXT NOT NULL,
			mxid TEXT,
			parent_id TEXT,
			parent_receiver TEXT NOT NULL DEFAULT '',
			relay_bridge_id TEXT,
			relay_login_id TEXT,
			other_user_id TEXT,
			name TEXT NOT NULL,
			topic TEXT NOT NULL,
			avatar_id TEXT NOT NULL,
			avatar_hash TEXT NOT NULL,
			avatar_mxc TEXT NOT NULL,
			name_set BOOLEAN NOT NULL,
			avatar_set BOOLEAN NOT NULL,
			topic_set BOOLEAN NOT NULL,
			name_is_custom BOOLEAN NOT NULL DEFAULT false,
			in_space BOOLEAN NOT NULL,
			message_request BOOLEAN NOT NULL DEFAULT false,
			room_type TEXT NOT NULL,
			disappear_type TEXT,
			disappear_timer BIGINT,
			cap_state TEXT,
			metadata TEXT NOT NULL,
			PRIMARY KEY (bridge_id, id, receiver)
		)`,
		`CREATE TABLE user_portal (
			bridge_id TEXT NOT NULL,
			user_mxid TEXT NOT NULL,
			login_id TEXT NOT NULL,
			portal_id TEXT NOT NULL,
			portal_receiver TEXT NOT NULL,
			in_space BOOLEAN NOT NULL,
			preferred BOOLEAN NOT NULL,
			last_read BIGINT
		)`,
		`CREATE TABLE user_login (
			bridge_id TEXT NOT NULL,
			user_mxid TEXT NOT NULL,
			id TEXT NOT NULL,
			remote_name TEXT NOT NULL,
			remote_profile TEXT,
			space_room TEXT,
			metadata TEXT NOT NULL
		)`,
		`INSERT INTO portal (bridge_id, id, receiver, mxid, name, topic, avatar_id, avatar_hash, avatar_mxc, name_set, avatar_set, topic_set, in_space, room_type, metadata)
		 VALUES ('whatsapp', 'chat-1', 'receiver-1', '!room1:example.com', 'Chat 1', '', '', '', '', 1, 1, 1, 0, 'dm', '{}')`,
		`INSERT INTO portal (bridge_id, id, receiver, mxid, name, topic, avatar_id, avatar_hash, avatar_mxc, name_set, avatar_set, topic_set, in_space, room_type, metadata)
		 VALUES ('whatsapp', 'chat-2', 'receiver-2', '!room2:example.com', 'Chat 2', '', '', '', '', 1, 1, 1, 0, 'dm', '{}')`,
		`INSERT INTO user_login (bridge_id, user_mxid, id, remote_name, remote_profile, space_room, metadata)
		 VALUES ('whatsapp', '@me:example.com', 'login-a', 'Phone A', '{}', '!spaceA:example.com', '{}')`,
		`INSERT INTO user_login (bridge_id, user_mxid, id, remote_name, remote_profile, space_room, metadata)
		 VALUES ('whatsapp', '@me:example.com', 'login-b', 'Phone B', '{}', NULL, '{}')`,
		`INSERT INTO user_portal (bridge_id, user_mxid, login_id, portal_id, portal_receiver, in_space, preferred, last_read)
		 VALUES ('whatsapp', '@me:example.com', 'login-a', 'chat-1', 'receiver-1', 0, 1, NULL)`,
		`INSERT INTO user_portal (bridge_id, user_mxid, login_id, portal_id, portal_receiver, in_space, preferred, last_read)
		 VALUES ('whatsapp', '@me:example.com', 'login-b', 'chat-2', 'receiver-2', 0, 0, NULL)`,
	}

	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("exec statement: %v\n%s", err, stmt)
		}
	}

	repo := NewRepository(dbPath)
	mappings, err := repo.ListRoomMappings(
		context.Background(),
		"@me:example.com",
		"whatsapp",
	)
	if err != nil {
		t.Fatalf("list room mappings: %v", err)
	}
	if len(mappings) != 2 {
		t.Fatalf("expected 2 mappings, got %d", len(mappings))
	}
	if mappings[0].RoomID != "!room1:example.com" || mappings[0].LoginID != "login-a" {
		t.Fatalf("unexpected first mapping: %+v", mappings[0])
	}
	if mappings[0].LoginName == nil || *mappings[0].LoginName != "Phone A" {
		t.Fatalf("unexpected login name: %+v", mappings[0])
	}
	if mappings[0].SpaceRoom == nil || *mappings[0].SpaceRoom != "!spaceA:example.com" {
		t.Fatalf("unexpected space room: %+v", mappings[0])
	}
	if !mappings[0].Preferred {
		t.Fatalf("expected first mapping to be preferred: %+v", mappings[0])
	}
}
