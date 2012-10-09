# Bash lambda

Real lambda support for bash (a functionally complete hack). Includes a set of
functions for functional programming, list allocation and traversal, and
concurrent mark/sweep garbage collection with weak reference support.

## Getting started

Load the library into your shell (the `source` line can go into .bashrc):
```
$ git clone git://github.com/spencertipping/bash-lambda
$ source bash-lambda/bash-lambda
```

## Defining functions

The functions provided by bash-lambda take their nomenclature from Clojure, and
they are as analogous as I could make them while remaining somewhat useful in a
bash context. They are, by example:

### Anonymous functions

These are created with the `fn` form and work like this:

```
$ $(fn name 'echo "hello there, $name"') spencer
hello there, spencer
$ greet=$(fn name 'echo "hello there, $name"')
$ $greet spencer
hello there, spencer
$
```

The spec is `fn formals... 'body'`. You can use an alternative form, `cons_fn`,
which takes the body from stdin: `cons_fn formals... <<'end'\n body \nend`.

### Named functions

These are created using `defn`:

```
$ defn greet name 'echo "hi there, $name"'
/tmp/blheap-xxxx-xxxxxxxxxxxxxxxxxxx/greet
$ greet spencer
hi there, spencer
$
```

Notice that we didn't need to dereference `greet` this time, since it's now a
named function instead of a variable.

You can use `def` to name any value:

```
$ def increment $(fn x 'echo $((x + 1))')
$ increment 10
11
$
```

### Partials and composition

Like Clojure, bash-lambda gives you functions to create partial (curried)
functions and compositions. These are called `partial` and `comp`, respectively.

```
$ add=$(fn x y 'echo $((x + y))')
$ $(partial $add 5) 6
11
$ $(comp $(partial $add 1) $(partial $add 2)) 5
8
$
```

## Lists

Bash-lambda gives you the usual suspects for list manipulation. However, there
are a few differences from the way they are normally implemented.

### Mapping over lists

```
$ map $(partial $add 5) $(list 1 2 3 4)
6
7
8
9
$ seq 1 4 | map $(partial $add 1)
2
3
4
5
$
```

The `list` function boxes up a series of values into a single file for later
use. It's worth noting that this won't work:

```
$ map $(partial $add 5) $(map $(partial $add 1) $(list 1 2 3))
cat: 2: No such file or directory
$
```

You need to wrap the inner `map` into a list if you want to use applicative
notation:

```
$ map $(partial $add 5) $(list $(map $(partial $add 1) $(list 1 2 3)))
7
8
9
$
```

Alternatively, just use pipes. This allows you to process lists of arbitrary
size.

```
$ map $(partial $add 1) $(list 1 2 3) | map $(partial $add 5)
7
8
9
$
```

### Reducing and filtering

Two functions `reduce` and `filter` do what you would expect. (`reduce` isn't
named `fold` like the Clojure function because `fold` is a useful shell utility
already)

```
$ reduce $add 0 $(list 1 2 3)
6
$ even=$(fn x '((x % 2 == 0))')
$ seq 1 10 | filter $even
2
4
6
8
10
$
```

Higher-order functions work like you would expect:

```
$ sum_list=$(partial reduce $add 0)
$ $sum_list $(list 1 2 3)
6
$ rand_int=$(fn 'echo $RANDOM')
$ repeatedly $rand_int 100 | $sum_list
1566864

$ our_numbers=$(list $(repeatedly $rand_int 100))
```

### Flatmap (mapcat in Clojure)

It turns out that `map` already does what you need to write `mapcat`. The lists
in bash-lambda behave more like Perl lists than like Lisp lists -- that is,
consing is associative, so things are flattened out unless you box them up into
files. Therefore, `mapcat` is just a matter of writing multiple values from a
function:

```
$ self_and_one_more=$(fn x 'echo $x; echo $((x + 1))')
$ map $self_and_one_more $(list 1 2 3)
1
2
2
3
3
4
$
```

## Closures

There are two ways you can allocate closures, one of which is true to the usual
Lisp way but is horrendously ugly:

```
$ average=$(fn xs "echo \$((\$($sum_list \$xs) / \$(wc -l < \$xs)))")
$ $average $our_numbers
14927
```

Here we're closing over the current value of `$sum_list` and emulating
Lisp-style quasiquoting by deliberately escaping everything else. (Well, with a
good bit of bash mixed in.)

The easier way is to make the 'average' function visible within closures by
giving it a name. While we're at it, let's do the same for `sum_list`; that way
we won't need to close over `$sum_list` and escape a bunch of variables.

```
$ def sum-list $sum_list
$ defn average xs 'echo $(($(sum-list $xs) / $(wc -l < $xs)))'
```

Named functions don't need to be dereferenced, since they aren't variables:

```
$ average $our_numbers
14927
```

Values are just files, so you can save one for later:

```
$ cp $our_numbers the-list
```

## Garbage collection

Bash-lambda implements a conservative concurrent mark-sweep garbage collector
that runs automatically if an allocation is made more than 30 seconds since the
last GC run. This prevents the disk from accumulating tons of unused files from
anonymous functions, partials, compositions, etc.

You can also trigger a synchronous GC by running the `bash_lambda_gc` function
(just `gc` for short):

```
$ bash_lambda_gc
0 0
$
```

The two numbers are the number and size of reclaimed objects. If it says `0 0`,
then no garbage was found.

### Pinning objects

The root set is built from all variables you have declared in your shell. This
includes any functions you've written, etc. However, there may be cases where
you need to pin a reference so that it will never be collected. You can do this
using `bash_lambda_gc_pin`, or just `gc_pin` for short:

```
$ pinned_function=$(gc_pin $(fn x 'echo $x'))
```

### Weak references

You can construct a weak reference to anything in the heap using `weak_ref`:

```
$ f=$(fn x 'echo hi')
$ g=$(weak_ref $f)
$ $f
hi
$ $g
hi
$ unset f
$ $g
hi
$ bash_lambda_gc
1 36
$ $g
no such file or directory
$
```

Weak references (and all references, for that matter) can be checked using
bash's `-e` test:

```
$ f=$(fn x 'echo hi')
$ exists=$(fn name '[[ -e $name ]] && echo yes || echo no')
$ $exists $f
yes
$ g=$(weak_ref $f)
$ $exists $g
yes
$ unset f
$ bash_lambda_gc
1 36
$ $exists $g
no
$
```

### Known problems with concurrent GC

Bash-lambda doesn't own its heap and memory space the same way that the JVM
does. As a result, there are a few cases where GC will be inaccurate, causing
objects to be collected when they shouldn't. So far these cases are:

1. The window of time between parameter substitution and command invocation.
   Allocations made by those parameter substitutions will be live but may be
   collected anyway since they are not visible in the process table.
2. By extension, any commands that have delayed parts:
   `sleep 10; map $(fn ...) $xs`. We can't read the memory of the bash process,
   so we won't be able to know whether the `$(fn)` is still in the live set.

See `src/gc` for a full discussion of these issues.
