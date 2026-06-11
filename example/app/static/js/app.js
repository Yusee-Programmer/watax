// watax-notes — small progressive-enhancement script.
// The app works fully via plain HTML form posts; this just adds a
// confirmation step before deleting a note.
document.addEventListener("DOMContentLoaded", function () {
    var deleteForms = document.querySelectorAll(".note-delete");
    for (var i = 0; i < deleteForms.length; i++) {
        deleteForms[i].addEventListener("submit", function (e) {
            if (!window.confirm("Delete this note?")) {
                e.preventDefault();
            }
        });
    }
});
