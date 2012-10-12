# Bash lambda

Real lambda support for bash (a functionally complete hack). Includes a set of
functions for functional programming, list allocation and traversal, futures,
complete closure serialization, remote closure execution, multimethods, and
concurrent mark/sweep garbage collection with weak reference support.

## NOTE

*This library is experimental.* Don't use it for mission-critical applications,
important data storage, etc. It's obviously a huge hack and may malfunction in
any number of awkward ways. None of these should impact the integrity of the
rest of your data (I source this library in my `.bashrc` and nothing bad has
happened yet), but it probably wouldn't hurt to glance over the source code
before using it, just in case.

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

Alternatively, just use pipes. This allows you to process lists lazily.

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

Another function, `reductions`, returns the intermediate results of reducing a
list:

```
$ seq 1 4 | reductions $add 0
1
3
6
10
$
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

### Infinite lists

UNIX has a long tradition of using pipes to form lazy computations, and
bash-lambda is designed to do the same thing. You can generate infinite lists
using `iterate` and `repeatedly`, each of which is roughly equivalent to the
Clojure function of the same name:

```
$ repeatedly $rand_int 100      # notice count is after, not before, function
<100 numbers>
$ iterate $(partial $add 1) 0
0
1
2
3
...
$
```

Note that both `iterate` and `repeatedly` will continue forever, even if you
use `take` (a wrapper for `head`) to select only a few lines. I'm not sure how
to fix this at the moment, but I'd be very happy to accept a fix if anyone has
one. (See `src/list` for these functions)

### Searching lists

Bash-lambda provides `some` and `every` to find list values. These behave like
Clojure's `some` and `every`, but each one returns the element it used to
terminate the loop, if any.

```
$ ls /bin/* | some $(fn '[[ -x $1 ]]')
/bin/bash
$ echo $?
0
$ ls /etc/* | every $(fn '[[ -d $1 ]]')
/etc/adduser.conf
$ echo $?
1
$
```

If `some` or `every` reaches the end of the list, then it outputs nothing and
its only result is its status code. (For `some`, it means nothing was found, so
it returns 1; for `every`, it means they all satisfied the predicate, so it
returns 0.)

It also gives you the `nth` function, which does exactly what you would expect:

```
$ nth 0 $(list 1 2 3)
1
$ list 1 2 3 | nth 2
3
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

The easier way is to make the 'sum_list' function visible within closures by
giving it a name. While we're at it, let's do the same for `average`.

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

## Atoms and locking

Atoms are atomic values that use spin or wait locks to provide transactions.
They are used extensively under the hood for things like futures, but in
general you will probably not find much use for them.

However, if you're curious, you should check out `src/atom` and
`src/semaphore`.

### Pipelocks

This provides an instant lock/release lock that doesn't incur the overhead of a
full spin or delay:

```
$ lock=$(pipelock)
$ ln -s $lock my-pipelock
$ pipelock_grab $lock           # blocks until...

other-terminal$ pipelock_release my-pipelock
other-terminal$

# ... we free it using pipelock_release from the other terminal
$
```

See `src/pipelock` for implementation details.

## Futures and remote execution

Futures are asynchronous processes that you can later force to get their
values. Bash-lambda implements the `future` function, which asynchronously
executes another function and allows you to monitor its status:

```
$ f=$(future $(fn 'sleep 10; echo hi'))
$ future_finished $f || echo waiting
waiting
$ time future_get $f
hi

real    0m7.707s
user    0m0.016s
sys     0m0.052s
$
```

### Futures as memoized results

When you create a future, standard out is piped into a file that is then
replayed. This file is preserved as long as you have live references to the
future object, so you can replay the command's output at very little cost. For
example:

```
$ f=$(future $(fn 'sleep 10; echo hi'))
$ time get $f   # long runtime
hi

real    0m8.436s
user    0m0.128s
sys     0m0.208s
$ time get $f   # short runtime; result is cached
hi

real    0m0.116s
user    0m0.044s
sys     0m0.060s
$
```

The exit code is also memoized; however, standard error and other side-effects
are not. There is no way to clear a future after it has finished executing.

### Futures and lists

You can transpose a list of futures into a future of a list using
`future_transpose`:

```
$ f=$(fn 'sleep 10; echo $RANDOM')
$ futures=$(list $(repeatedly $(partial future $f) 10))
$ single=$(future_transpose $futures)
$ future_finished $single || echo waiting
waiting
$ future_get $single    # takes a moment
21297
26453
28753
23369
21573
19249
25975
12058
21774
469
$
```

The resulting list is order-preserving.

Both `future_finished` and `future_get` are implemented as multimethods, so you
can simply use `finished` and `get` instead.

### Parallel mapping

You can apply bounded parallelism to the elements of a list by using
`parallel_map`. This function returns a lazily computed list of futures; if you
need all of the results at once, you can use `future_transpose`.

The advantage of `parallel_map $f` over `map $(comp future $f)` is that you can
limit the maximum number of running jobs. This lets you have functionality
analogous to `make -jN`, but for general-purpose list mapping. Like `map`,
`parallel_map` is order-preserving. For example:

```
$ compile=$(fn cfile 'gcc $cfile -o ${cfile%.c}')
$ futures=$(list $(ls | parallel_map $compile))
$ map get $futures      # force each one
...
$
```

### Remote execution

The `remote` function sends a function, along with any heap dependencies it
has, to another machine via SSH and runs it there, piping back the standard
output to the local machine. For example:

```
$ check_disk_space=$(fn 'df -h')
$ remote some-machine $check_disk_space
...
Filesystem Size Used Avail Use% Mounted on
/dev/sda1  250G 125G  125G  50% /
...
$
```

This can be useful in conjunction with futures.

## Multimethods

These aren't quite as cool as the ones in Clojure (and they're a lot slower),
but bash-lambda implements multimethods that allow you to have OO-style
polymorphism. This is based around the idea of a `ref_type`, which is a
filename prefix that gets added to various kinds of objects:

```
$ map ref_type $(list $(list) $(fn 'true') $(pipelock) $(semaphore 5))
list
fn
pipelock
semaphore
$
```

Whenever you have a function called `$(ref_type $x)_name`, for instance
`future_get`, you can omit the `future_` part if you're passing an object with
that `ref_type` as the first argument (which you often do). So:

```
$ get $(future $(fn 'echo hi'))
hi
$ future_get $(future $(fn 'echo hi'))
hi
$ get $(atom 100)
100
$ atom_get $(atom 100)
100
$
```

You use `defmulti` to define a new multimethod. Examples of this are in
`src/multi`.

## References and garbage collection

Bash-lambda implements a conservative concurrent mark-sweep garbage collector
that runs automatically if an allocation is made more than 30 seconds since the
last GC run. This prevents the disk from accumulating tons of unused files from
anonymous functions, partials, compositions, etc.

You can also trigger a synchronous GC by running the `bash_lambda_gc` function:

```
$ bash_lambda_gc
0 0
$
```

The two numbers are the number and size of reclaimed objects. If it says `0 0`,
then no garbage was found.

### Saving complete references

You can serialize any anonymous function, composition, partial application,
list, or completed future (you can't serialize a running future for obvious
reasons). To do that, use the `ref_snapshot` function, which returns the
filename of a heap-allocated tar.gz file:

```
$ f=$(fn x 'echo $((x + 1))')
$ g=$(comp $f $f)
$ h=$(comp $g $f)
$ ref_snapshot $h
/tmp/blheap-12328-29f272454ea973c4561b2d1238957b7d0b2c/snapshot_u2C3u3QXO3cRpQ
$ tar -tvf $(ref_snapshot $h)
-rwx------ spencertipping/spencertipping 44 2012-10-11 23:01 /tmp/blheap-12328-29f272454ea973c4561b2d1238957b7d0b2c/fn_mm7fTv75AQZ4lf
-rwx------ spencertipping/spencertipping 174 2012-10-11 23:01 /tmp/blheap-12328-29f272454ea973c4561b2d1238957b7d0b2c/fn_oiKxIgZQwPnmTD
-rwx------ spencertipping/spencertipping 174 2012-10-11 23:01 /tmp/blheap-12328-29f272454ea973c4561b2d1238957b7d0b2c/fn_Uq2O7rtISqbfw3
$
```

This tar.gz file will be garbage-collected just like any other object. You can
extract a heap snapshot on the same or a different machine by using `tar
-xzPf`, or by using `ref_intern`:

```
$ def f $(comp ...)
$ scp $(ref_snapshot $BASH_LAMBDA_HEAP/f) other-machine:snapshot
$ ssh other-machine
other-machine$ ref_intern snapshot
other-machine$ original-heap-name/f
```

Notice that you'll need to communicate not only the function's data but also
its name; `ref_snapshot` and `ref_intern` are low-level functions that aren't
designed to be used directly for remoting (though they probably do most of the
work).

### Inspecting heap state

You can see how much memory the heap is using by running `heap_stats`:

```
$ heap_stats
heap size:           120K
objects:             54
permanent:           54
$
```

You can also inspect the root set and find the immediate references for any
object:

```
$ gc_roots | ref_children
/tmp/blheap-xxxx-xxxxxxxxxxx/gc_roots
/tmp/blheap-xxxx-xxxxxxxxxxx/gc_roots
/tmp/blheap-xxxx-xxxxxxxxxxx/gc_roots
$ add=$(fn x y 'echo $((x + y))')
$ echo $add
/tmp/blheap-xxxx-xxxxxxxxxxx/fn_xxxx_xxxxxxxxx
$ cat $(partial $add 5) | gc_refs
/tmp/blheap-xxxx-xxxxxxxxxxx/fn_xxxx_xxxxxxxxx
$
```

The output of `ref_children` includes weak references. You can detect weak or
fictitious references by looking for slashes in whatever follows
`$BASH_LAMBDA_HEAP/`:

```
$ is_real_ref=$(fn x '[[ ! ${x##$BASH_LAMBDA_HEAP/} =~ / ]]')
$ $is_real_ref $is_real_ref || echo not real
$ $is_real_ref $(weak_ref $is_real_ref) || echo not real
not real
$
```

If you need the full transitive closure, you can use `ref_closure`. This
function encapsulates the algorithm used by the GC to find live references.

### Pinning objects

The root set is built from all variables you have declared in your shell and
all running processes. This includes any functions you've written, etc.
However, there may be cases where you need to pin a reference so that it will
never be collected. You can do this using `bash_lambda_gc_pin`, or just
`gc_pin` for short:

```
$ pinned_function=$(gc_pin $(fn x 'echo $x'))
```

You can use an analogous function, unpin, to remove something's pinned status:

```
$ f=$(gc_unpin $pinned_function)
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

### Limits of concurrent GC in bash

Bash-lambda doesn't own its heap and memory space the same way that the JVM
does. As a result, there are a few cases where GC will be inaccurate, causing
objects to be collected when they shouldn't. So far these cases are:

1. The window of time between parameter substitution and command invocation.
   Allocations made by those parameter substitutions will be live but may be
   collected anyway since they are not visible in the process table.
2. ~~By extension, any commands that have delayed parts:
   `sleep 10; map $(fn ...) $xs`. We can't read the memory of the bash
   process, so we won't be able to know whether the `$(fn)` is still in the
   live set.~~
   This is incorrect. Based on some tests I ran, `$()` expressions inside
   delayed commands are evaluated only once the delayed commands are.
   Therefore, the only cause of pathological delays would be something like
   this: `cat $(fn 'echo hi'; sleep 10)`, which would delay the visibility of
   the `$(fn)` form.

Bash-lambda does its best to work around these problems, but there may still be
edge cases. See `src/gc` for a full discussion of these issues, and please let
me know if you run into bugs in the garbage collector.
