//go:build !consulent
// +build !consulent

package peering_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/hashicorp/consul/proto/pbpeering"
)

func TestPeeringService_RejectsPartition(t *testing.T) {
	s := newTestServer(t, nil)
	client := pbpeering.NewPeeringServiceClient(s.ClientConn(t))

	t.Run("read", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		t.Cleanup(cancel)

		req := &pbpeering.PeeringReadRequest{Name: "foo", Partition: "default"}
		resp, err := client.PeeringRead(ctx, req)
		require.Contains(t, err.Error(), "Partitions are a Consul Enterprise feature")
		require.Nil(t, resp)
	})

	t.Run("list", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		t.Cleanup(cancel)

		req := &pbpeering.PeeringListRequest{Partition: "default"}
		resp, err := client.PeeringList(ctx, req)
		require.Contains(t, err.Error(), "Partitions are a Consul Enterprise feature")
		require.Nil(t, resp)
	})
}