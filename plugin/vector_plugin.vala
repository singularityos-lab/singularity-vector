namespace VectorPlugin {

    public interface Host : Object {
        public abstract string document_json { owned get; set; }
        public abstract string[] selection_ids { owned get; }
        public abstract void run_action (string name);
        public abstract void select_ids (string[] ids);
        public abstract void message (string text);
    }

    public interface Command : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract void run (Host host) throws Error;
    }

    public interface Exporter : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract string suffix { owned get; }
        public abstract uint8[] export (string document_json) throws Error;
    }
}
