const RelationSearch = {
  mounted() {
    this._onInput = () => {
      this.pushEvent("search_relations", {relation_query: this.el.value || ""})
    }

    this.el.addEventListener("input", this._onInput)
  },

  destroyed() {
    this.el.removeEventListener("input", this._onInput)
  }
}

export default RelationSearch
