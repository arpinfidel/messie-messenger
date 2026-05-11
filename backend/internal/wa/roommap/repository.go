package roommap

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"

	_ "github.com/mattn/go-sqlite3"
)

type Mapping struct {
	Provider  string
	RoomID    string
	LoginID   string
	LoginName *string
	SpaceRoom *string
	Preferred bool
}

type Repository struct {
	dbPath string
}

func NewRepository(dbPath string) *Repository {
	return &Repository{dbPath: dbPath}
}

func (r *Repository) ListRoomMappings(
	ctx context.Context,
	userMXID string,
	provider string,
) ([]Mapping, error) {
	if r == nil || r.dbPath == "" {
		return nil, fmt.Errorf("bridge db path not configured")
	}

	dsn := fmt.Sprintf(
		"file:%s?mode=ro&_busy_timeout=5000",
		url.PathEscape(r.dbPath),
	)
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, fmt.Errorf("open bridge db: %w", err)
	}
	defer db.Close()

	rows, err := db.QueryContext(
		ctx,
		`
SELECT
  p.mxid,
  up.login_id,
  ul.remote_name,
  ul.space_room,
  up.preferred
FROM user_portal up
JOIN portal p
  ON p.bridge_id = up.bridge_id
 AND p.id = up.portal_id
 AND p.receiver = up.portal_receiver
LEFT JOIN user_login ul
  ON ul.bridge_id = up.bridge_id
 AND ul.user_mxid = up.user_mxid
 AND ul.id = up.login_id
WHERE up.user_mxid = ?
  AND p.mxid IS NOT NULL
ORDER BY up.preferred DESC, ul.remote_name ASC, up.login_id ASC, p.mxid ASC
`,
		userMXID,
	)
	if err != nil {
		return nil, fmt.Errorf("query bridge room mappings: %w", err)
	}
	defer rows.Close()

	var mappings []Mapping
	for rows.Next() {
		var mapping Mapping
		mapping.Provider = provider
		var loginName sql.NullString
		var spaceRoom sql.NullString
		if err := rows.Scan(
			&mapping.RoomID,
			&mapping.LoginID,
			&loginName,
			&spaceRoom,
			&mapping.Preferred,
		); err != nil {
			return nil, fmt.Errorf("scan bridge room mapping: %w", err)
		}
		if loginName.Valid {
			mapping.LoginName = &loginName.String
		}
		if spaceRoom.Valid {
			mapping.SpaceRoom = &spaceRoom.String
		}
		mappings = append(mappings, mapping)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bridge room mappings: %w", err)
	}
	return mappings, nil
}
