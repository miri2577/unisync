/// Generic labeled tree data structure.
///
/// Mirrors OCaml Unison's `tree.ml`. Used for hierarchical storage of
/// reconciliation results and update items.
library;

/// A tree with labeled arcs of type [A] and node/leaf values of type [B].
///
/// - [Leaf] is a terminal node with a value.
/// - [Node] has labeled children and an optional value at the node itself.
sealed class Tree<A, B> {
  const Tree();
}

/// Terminal tree node with a value.
class Leaf<A, B> extends Tree<A, B> {
  final B value;
  const Leaf(this.value);
}

/// Interior tree node with labeled children and optional node value.
class Node<A, B> extends Tree<A, B> {
  /// Labeled child subtrees.
  final List<(A, Tree<A, B>)> children;

  /// Optional value at this node (not just at leaves).
  final B? value;

  const Node(this.children, [this.value]);
}

/// Extension methods for tree operations.
extension TreeOps<A, B> on Tree<A, B> {
  /// Depth-first traversal, calling [f] with the path of arc labels
  /// and leaf/node values.
  void iteri(void Function(List<A> path, B value) f, [List<A>? prefix]) {
    final path = prefix ?? <A>[];
    switch (this) {
      case Leaf<A, B>(value: var v):
        f(path, v);
      case Node<A, B>(children: var cs, value: var v):
        if (v != null) f(path, v);
        for (final (label, child) in cs) {
          child.iteri(f, [...path, label]);
        }
    }
  }

  /// Flatten tree into a list of (path, value) pairs via DFS.
  List<(List<A>, B)> flatten() {
    final result = <(List<A>, B)>[];
    iteri((path, value) => result.add((List.of(path), value)));
    return result;
  }

  /// Map both arc labels and values.
  Tree<A2, B2> map<A2, B2>(
    A2 Function(A) mapArc,
    B2 Function(B) mapValue,
  ) {
    return switch (this) {
      Leaf<A, B>(value: var v) => Leaf(mapValue(v)),
      Node<A, B>(children: var cs, value: var v) => Node(
          cs
              .map((e) => (mapArc(e.$1), e.$2.map(mapArc, mapValue)))
              .toList(growable: false),
          v != null ? mapValue(v) : null,
        ),
    };
  }

  /// Map only the values, keeping arc labels unchanged.
  Tree<A, B2> mapValues<B2>(B2 Function(B) f) => map((a) => a, f);

  /// Check if the tree is empty (no values anywhere).
  bool get isTreeEmpty {
    return switch (this) {
      Leaf<A, B>() => false,
      Node<A, B>(children: var cs, value: var v) =>
        v == null && cs.every((e) => e.$2.isTreeEmpty),
    };
  }
}

/// Builder for incrementally constructing a tree.
///
/// Matches OCaml's `start/add/enter/leave/finish` API.
class TreeBuilder<A, B> {
  final List<_BuildFrame<A, B>> _stack = [];

  TreeBuilder() {
    _stack.add(_BuildFrame());
  }

  /// Add a leaf at the current level.
  void add(A label, B value) {
    _stack.last.children.add((label, Leaf<A, B>(value)));
  }

  /// Enter a new child level with the given arc label.
  void enter(A label) {
    _stack.add(_BuildFrame(parentLabel: label));
  }

  /// Leave the current level, building a Node.
  void leave({B? nodeValue}) {
    if (_stack.length < 2) {
      throw StateError('Cannot leave root level');
    }
    final frame = _stack.removeLast();
    final node = Node<A, B>(frame.children, nodeValue);
    _stack.last.children.add((frame.parentLabel as A, node));
  }

  /// Finish building and return the root tree.
  Tree<A, B> finish({B? rootValue}) {
    if (_stack.length != 1) {
      throw StateError(
        'Unbalanced enter/leave: ${_stack.length - 1} unclosed levels',
      );
    }
    final frame = _stack.first;
    if (frame.children.isEmpty && rootValue != null) {
      return Leaf<A, B>(rootValue);
    }
    return Node<A, B>(frame.children, rootValue);
  }
}

class _BuildFrame<A, B> {
  final Object? parentLabel;
  final List<(A, Tree<A, B>)> children = [];

  _BuildFrame({this.parentLabel});
}
