<p align="center">
  <img src="icon.png" width="96" alt="Markview">
</p>

<h1 align="center">Markview</h1>

<p align="center">
  <a href="https://example.com"><img src="https://img.shields.io/badge/build-passing-brightgreen" alt="build"></a>
  <a href="https://example.com"><img src="https://img.shields.io/badge/license-MIT-blue" alt="license"></a>
</p>

<p align="center"><a href="https://example.com"><b>Website</b></a> · <a href="#tables">Tables</a> · <code>brew install markview</code></p>

<!-- A comment. It must not show. -->

A README often mixes HTML into its Markdown. Markview understands the common
elements and drops the rest, keeping their text.

<div align="center">

## Markdown inside a centred div

This heading and paragraph are centred by the `<div align="center">` around them.

</div>

## Details

<details>
<summary>Click to expand (always shown expanded here)</summary>

Hidden *Markdown* content, with a list:

- one
- two

</details>

## Inline tags

Water is H<sub>2</sub>O, E = mc<sup>2</sup>, press <kbd>⌘</kbd> + <kbd>S</kbd>,
<b>bold</b>, <i>italic</i>, <u>underlined</u>, <s>struck</s>, <code>code</code>,
<a href="https://example.com">a link</a>, line one<br>line two.

Entities: &copy; &amp; &lt;tag&gt; &quot;quoted&quot; &rarr; &mdash; done.

## Tables

<table>
  <thead>
    <tr><th>Feature</th><th>Markdown</th><th>HTML</th></tr>
  </thead>
  <tbody>
    <tr><td>Column spans</td><td colspan="2">yes, this cell spans two columns</td></tr>
    <tr><td rowspan="2">Row spans</td><td>no</td><td>yes</td></tr>
    <tr><td>(continued)</td><td align="right">right aligned</td></tr>
  </tbody>
</table>

## Lists, rules and code

<ul>
  <li>An HTML list item</li>
  <li>With a nested ordered list
    <ol><li>first</li><li>second</li></ol>
  </li>
</ul>

<hr>

<pre><code class="language-python">def hello(name):
    return f"Hello, {name}"   # a pre/code block with a language class
</code></pre>

## Dropped

Scripts, styles and unknown tags leave no trace: <script>alert("no")</script><style>body { color: red }</style><blink>text kept</blink>, <span class="x">span text kept</span>.

<a name="end"></a>The end.