import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Tree', () {
    test('Leaf holds value', () {
      const tree = Leaf<String, int>(42);
      expect(tree.value, 42);
    });

    test('Node with children', () {
      const tree = Node<String, int>([
        ('a', Leaf(1)),
        ('b', Leaf(2)),
      ]);
      expect(tree.children.length, 2);
    });

    test('flatten collects all values with paths', () {
      const tree = Node<String, int>([
        ('a', Leaf(1)),
        ('b', Node([
          ('c', Leaf(2)),
          ('d', Leaf(3)),
        ])),
      ]);
      final flat = tree.flatten();
      expect(flat.length, 3);
      expect(flat[0].$1, ['a']);
      expect(flat[0].$2, 1);
      expect(flat[1].$1, ['b', 'c']);
      expect(flat[1].$2, 2);
      expect(flat[2].$1, ['b', 'd']);
      expect(flat[2].$2, 3);
    });

    test('iteri visits all nodes', () {
      const tree = Node<String, int>([
        ('x', Leaf(10)),
        ('y', Leaf(20)),
      ]);
      final visited = <(List<String>, int)>[];
      tree.iteri((path, value) => visited.add((List.of(path), value)));
      expect(visited.length, 2);
      expect(visited[0].$2, 10);
      expect(visited[1].$2, 20);
    });

    test('mapValues transforms values', () {
      const tree = Node<String, int>([
        ('a', Leaf(1)),
        ('b', Leaf(2)),
      ]);
      final doubled = tree.mapValues((v) => v * 2);
      final flat = doubled.flatten();
      expect(flat[0].$2, 2);
      expect(flat[1].$2, 4);
    });

    test('isTreeEmpty for empty node', () {
      const tree = Node<String, int>([], null);
      expect(tree.isTreeEmpty, isTrue);
    });

    test('isTreeEmpty for non-empty node', () {
      const tree = Node<String, int>([('a', Leaf(1))]);
      expect(tree.isTreeEmpty, isFalse);
    });

    test('Node with value at node level', () {
      const tree = Node<String, int>([
        ('a', Leaf(1)),
      ], 99);
      final flat = tree.flatten();
      expect(flat.length, 2);
      expect(flat[0].$1, <String>[]);
      expect(flat[0].$2, 99);
      expect(flat[1].$1, ['a']);
      expect(flat[1].$2, 1);
    });
  });

  group('TreeBuilder', () {
    test('builds simple tree', () {
      final b = TreeBuilder<String, int>();
      b.add('a', 1);
      b.add('b', 2);
      final tree = b.finish();
      final flat = tree.flatten();
      expect(flat.length, 2);
    });

    test('builds nested tree', () {
      final b = TreeBuilder<String, int>();
      b.add('a', 1);
      b.enter('b');
      b.add('c', 2);
      b.add('d', 3);
      b.leave();
      final tree = b.finish();
      final flat = tree.flatten();
      expect(flat.length, 3);
      expect(flat[0].$1, ['a']);
      expect(flat[0].$2, 1);
      expect(flat[1].$1, ['b', 'c']);
      expect(flat[1].$2, 2);
      expect(flat[2].$1, ['b', 'd']);
      expect(flat[2].$2, 3);
    });

    test('throws on unbalanced leave', () {
      final b = TreeBuilder<String, int>();
      expect(() => b.leave(), throwsStateError);
    });

    test('throws on unbalanced enter', () {
      final b = TreeBuilder<String, int>();
      b.enter('x');
      expect(() => b.finish(), throwsStateError);
    });
  });
}
