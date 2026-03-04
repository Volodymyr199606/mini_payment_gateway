# frozen_string_literal: true

module Ai
  module ContextGraph
    # In-memory graph of doc sections. Nodes keyed by "#{file}##{anchor}".
    # Edges: parent_of, prev, next, links_to.
    class Graph
      attr_reader :nodes

      def initialize(nodes = {})
        @nodes = nodes.transform_keys(&:to_s)
      end

      # Returns related node_ids with edge types: [{ node_id:, edge_type: }]
      # edge_type: :parent, :child, :prev, :next, :links_to
      def neighbors(node_id)
        node = @nodes[node_id.to_s]
        return [] unless node

        result = []
        result << { node_id: node[:parent_id], edge_type: :parent } if node[:parent_id]
        node[:children_ids].to_a.each { |id| result << { node_id: id, edge_type: :child } }
        result << { node_id: node[:prev_id], edge_type: :prev } if node[:prev_id]
        result << { node_id: node[:next_id], edge_type: :next } if node[:next_id]
        node[:outgoing_link_ids].to_a.each { |id| result << { node_id: id, edge_type: :links_to } }
        result.compact
      end

      # Returns section metadata for node_id, or nil.
      def get(node_id)
        @nodes[node_id.to_s]
      end
    end
  end
end
